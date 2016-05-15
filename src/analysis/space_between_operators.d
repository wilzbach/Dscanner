// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module analysis.space_between_operators;

import dparse.lexer;
import dparse.ast;
import analysis.base : BaseAnalyzer;

// creates an visit method with a fixed inline method text
template WhiteSpaceMixin(string inline, NodeNames...)
{
    string whitespace()
    {
        string whiteSpaceExpressionTmp;
        foreach (NodeName; NodeNames)
        {
            whiteSpaceExpressionTmp ~= "override void visit(const " ~ NodeName ~ " expr)\n"
            ~ "{\n"
            ~ inline ~ "\n"
            ~ "}\n";
        }
        return whiteSpaceExpressionTmp;
    }

    enum WhiteSpaceMixin = whitespace();
}

/**
Checks that there is space between operators, assignment and statements
OK: a = 1;
NOT: a=1;
OK: a + 1;
NOT: a+1;
OK: for(;;) {};
NOT: for(;;){};
*/
class SpaceBetweenOperators : BaseAnalyzer
{
    ubyte[] code;
    size_t[size_t] lines;

    ///
	this(string fileName, ubyte[] code, bool skipTests = false)
	{
		super(fileName, null, skipTests);
		this.code = code;
        indexNewlines();
    }

    // length 1
    mixin(WhiteSpaceMixin!("checkForWhitespaceLength!1(expr.line, expr.column - 1); ASTVisitor.visit(expr);",
                           "AddExpression", "AndExpression", "OrExpression", "MulExpression", "XorExpression"));

    // length 2
    mixin(WhiteSpaceMixin!("checkForWhitespaceLength!2(expr.line, expr.column - 1); ASTVisitor.visit(expr);",
                            "AndAndExpression", "EqualExpression", "OrOrExpression", "PowExpression"));

    // length at most 3
    mixin(WhiteSpaceMixin!("checkForWhitespaceLength!3(expr.line, expr.column - 1); ASTVisitor.visit(expr);",
                            "InExpression", "IdentityExpression"));

    override void visit(const ShiftExpression expr)
    {
        checkForWhitespaceSymbols!(['<', '>'])(expr.line, expr.column - 1);
        ASTVisitor.visit(expr);
    }

    override void visit(const RelExpression expr)
    {
        checkForWhitespaceSymbols!(['<', '>', '=', '!'])(expr.line, expr.column - 1);
        ASTVisitor.visit(expr);
    }

    mixin(WhiteSpaceMixin!("isWhitespace(expr.startIndex - 1); ASTVisitor.visit(expr);",
                                "WhileStatement", "IfStatement", "ForStatement",
                                "ForeachStatement"));


    override void visit(const AssignExpression expr)
    {
        checkForWhitespaceLength!1(expr.line, expr.column - 1);
        ASTVisitor.visit(expr);
    }

    override void visit(const VariableDeclaration v)
    {
        foreach(const d; v.declarators)
        {
            checkForWhitespaceLength!1(d.name.line, d.name.column + d.name.text.length);
        }
        ASTVisitor.visit(v);
    }

    override void visit(const TernaryExpression expr)
    {
        checkForWhitespaceLength!1(expr.colon.line, expr.colon.column);
        ASTVisitor.visit(expr);
    }

	alias visit = ASTVisitor.visit;

private:


    /**
    Indexes all lines for fast access
    */
    void indexNewlines()
    {
        import std.utf: byCodeUnit, codeLength;
        size_t line = 0;
        size_t offset = 0;
        lines[0] = 0;
        // we don't need to care about utf8 here, newlines are unique
        foreach (s; (cast(char[]) code))
        {
            if (s == '\n')
            {
                lines[line] = offset;
                line++;
            }
            offset++;
        }
    }

    void checkForWhitespaceLength(size_t length)(size_t line, size_t column)
    {
        auto fun = (char s, size_t count) => (count <= length);
        checkForWhitespace(line, column, fun);
    }

    void checkForWhitespaceSymbols(char[] symbols)(size_t line, size_t column)
    {
        import std.algorithm: canFind;
        auto fun = (char s, size_t count) => symbols.canFind(s);
        checkForWhitespace(line, column, fun);
    }

    /**
        Checks whether there
          1) at least one whitespace character
          2) an arbitrary amount of non-whitespace character
          3) followed by at least one whitespace character
        pattern: (>= 1 whitespace) [^ ]* (>=1 whitespace)
    */
    void checkForWhitespace(H)(size_t line, size_t column, H pred)
    {
        import std.ascii: isWhite;
        import std.utf: byCodeUnit;
        auto offset = lines[line-2] + column;
        // all our characters are ascii, hence we don't need to care about
        // complicated encodings
        auto it = (cast(char[]) code[offset..$]).byCodeUnit;
        bool initalPhase = true;
        bool whitespaceSeen;
        size_t currentMiddleLength = 0;
        for (size_t second_offset = 0; !it.empty; second_offset++)
        {
            // require at least one whitespace per phase
            if (isWhite(it.front))
            {
                whitespaceSeen = true;
                if (!initalPhase)
                    break;
            }
            else
            {
                // allow an arbitrary amount of non-whitespace characters
                // followed by the whitespace
                if (initalPhase)
                {
                    if (!whitespaceSeen)
                    {
                        addErrorMessage(line, column + second_offset, KEY, MESSAGE);
                        return;
                    }
                    else
                    {
                        initalPhase = false;
                        whitespaceSeen = false;
                    }
                }
                currentMiddleLength++;
                // check whether we are over the length
                if (!pred(it.front, currentMiddleLength))
                {
                    addErrorMessage(line, column + second_offset, KEY, MESSAGE);
                }
            }
            it.popFront();
        }
        // we never found a second whitespace
        if (!whitespaceSeen)
            addErrorMessage(line, column, KEY, MESSAGE);
    }

    /**
    Is the character whitespace?
    */
    void isWhitespace(size_t start)
    {
        assert(start > 0);
        import std.ascii: isWhite;
        if (!isWhite(code[start]))
        {
            auto t = getLineForStart(start);
            addErrorMessage(t.line, t.column,
                            KEY, MESSAGE);
        }
    }

    /**
    Get the line & column for an index position
    */
    auto getLineForStart(size_t start)
    {
        import std.typecons;
        import std.array: byPair;
        size_t lowestLine = 0;
        size_t highestOffset = 0;
        foreach (line, offset; lines.byPair)
        {
            if (offset < start && offset >= highestOffset)
            {
                highestOffset = offset;
                lowestLine = line;
            }
        }
        return tuple!("line", "column")(lowestLine+2, start - lowestLine);
    }

    enum string KEY = "dscanner.style.space_between_operators";
	enum string MESSAGE = "Space between operators required";
}

unittest
{
	import analysis.config : StaticAnalysisConfig;
    import analysis.helpers;
    import std.stdio;

	StaticAnalysisConfig sac;
	sac.space_between_operators = "enabled";


	assertAnalyzerWarnings(q{
        void testOps()
        {
            // utf8 chars: 你好，世界
            auto a1 = 1+2; // [warn]: Space between operators required
            auto a1l = 1 +2; // [warn]: Space between operators required
            auto a1r = 1+ 2; // [warn]: Space between operators required
            a1 = 1+2; // [warn]: Space between operators required
            a1 = 1 +2; // [warn]: Space between operators required
            a1 = 1+ 2; // [warn]: Space between operators required
            auto a2 = 1 + 2;
            a2 = 1 + 2;
            auto b1 = 1-1; // [warn]: Space between operators required
            b1 = 1-1; // [warn]: Space between operators required
            auto b2 = 1 - 1;
            b2 = 1 - 1;
            auto c1 = 1/1; // [warn]: Space between operators required
            c1 = 1/1; // [warn]: Space between operators required
            auto c2 = 1 / 1;
            c2 = 1 / 1;
            auto d1 = 1*1; // [warn]: Space between operators required
            d1 = 1*1; // [warn]: Space between operators required
            auto d2 = 1 * 1;
            d2 = 1 * 1;
            auto e1 = 1%1; // [warn]: Space between operators required
            e1 = 1%1; // [warn]: Space between operators required
            auto e2 = 1 % 1;
            e2 = 1 % 1;
            auto f1 = 1^^1; // [warn]: Space between operators required
            f1 = 1^^1; // [warn]: Space between operators required
            auto f2 = 1 ^^ 1;
            f2 = 1 ^^ 1;
            auto g1 = 1||1; // [warn]: Space between operators required
            auto g1l = 1 ||1; // [warn]: Space between operators required
            auto g1r = 1|| 1; // [warn]: Space between operators required
            g1 = 1||1; // [warn]: Space between operators required
            g1 = 1 ||1; // [warn]: Space between operators required
            g1 = 1|| 1; // [warn]: Space between operators required
            auto g2 = 1 || 1;
            g2 = 1 || 1;
            auto h1 = 1&&1; // [warn]: Space between operators required
            h1 = 1&&1; // [warn]: Space between operators required
            auto h2 = 1 && 1;
            h2 = 1 && 1;
            a = 3+4; // [warn]: Space between operators required
            a = 3 +4; // [warn]: Space between operators required
            a = 3+ 4; // [warn]: Space between operators required
            a = 3 + 4;
        }
        void nestedOps()
        {
            int a = (3+4) + 2; // [warn]: Space between operators required
            a = (3 + 4)+ 2; // [warn]: Space between operators required
            a = 3 +4 - 2; // [warn]: Space between operators required
            a = (3 + 4) + 2;
            a = 3 + 4 - 2;
            a = 3 + 4 - (2 % 5);
        }
        void moreOps()
        {
            int a = 2>>1 + 2; // [warn]: Space between operators required
            a = 2 >>1 + 2; // [warn]: Space between operators required
            a = 2>> 1 + 2; // [warn]: Space between operators required
            a = 2 >> 1 + 2;
            a = 2>>>1 + 2; // [warn]: Space between operators required
            a = 2 >>>1 + 2; // [warn]: Space between operators required
            a = 2>>> 1 + 2; // [warn]: Space between operators required
            a = 2 >>> 1 + 2;
        }
        void testDeclarations()
        {
            int c= 1; // [warn]: Space between operators required
            int c =1; // [warn]: Space between operators required
            int c = 1; // OK
        }
        void testStatements()
        {
            if(true) {} // [warn]: Space between operators required
            if (true) {}
            while(true) {} // [warn]: Space between operators required
            while (true) {}
            foreach(s;[1]) {} // [warn]: Space between operators required
            foreach (s;[1]) {}
            foreach_reverse(s;[1]) {} // [warn]: Space between operators required
            foreach_reverse (s;[1]) {}
        }
        void testExpression()
        {
            auto a = true ? 1:0; // [warn]: Space between operators required
            auto a = true?1 : 0; // [warn]: Space between operators required
        }
	}c, sac);


	stderr.writeln("Unittest for SpaceBetweenOperators passed.");
}
