import std.algorithm;
import std.conv;
import std.file;
import std.net.curl;
import std.range;
import std.stdio;
import std.string;
import std.utf;
import stdx.data.json;

void main()
{
    string specVersion = "0.28";
    string specFile = "spec.json";
    if (!exists(specFile))
        download("http://spec.commonmark.org/" ~ specVersion ~ "/spec.json", specFile);

    auto failuresJSON = toJSONValue("failures.json".readText());
    string[] failureReasons = failuresJSON["reasons"].to!(JSONValue[]).map!(reason => reason.to!string).array();
    JSONValue[string] expectedFailureExamples = cast(JSONValue[string]) failuresJSON["examples"];
    auto ddoc = File("ddoc-commonmark-spec.d", "w");
    ddoc.write(r"// PERMUTE_ARGS:
// REQUIRED_ARGS: -D -Dd${RESULTS_DIR}/compilable -o-
// POST_SCRIPT: compilable/extra-files/ddocAny-postscript.sh markdown
// EXTRA_SOURCES: extra-files/commonmark-spec.ddoc

/++
Tests for DDoc's limited support of the [the CommonMark spec version ", specVersion, "](http://spec.commonmark.org/", specVersion, r"/).

Please note that examples that use `---` have it replaced with `___` or `***`,
to avoid conflicting with DDoc code sections. There are [expected
example failures](#fail_reasons) too, because [DDoc does not implement the
full CommonMark spec](https://dlang.org/spec/ddoc.html#markdown_differences).
$(REQUIRE_JAVASCRIPT)

$(TEST_TOTALS)

# Spec Examples:
+/");

    auto specJSON = specFile.readText();
	specJSON.strip();
	specJSON.skipOver("[");
    string currentSection;

	while (specJSON.length > 1)
	{
		auto test = specJSON.parseJSONValue();
        string exampleNumber = cast(string) test["example"];
        string section = cast(string) test["section"];

        if (section != currentSection)
        {
            currentSection = section;
            ddoc.write("\n/// ## ", section);
        }

		ddoc.write("\n/++\n$(EXAMPLE_HEADER ", exampleNumber, ")\n");

        bool expectFailure = (exampleNumber in expectedFailureExamples) !is null;
        bool exclude = expectFailure && "exclude" in expectedFailureExamples[exampleNumber] && cast(bool) expectedFailureExamples[exampleNumber]["exclude"];
        string failReason = expectFailure ? cast(string) expectedFailureExamples[exampleNumber]["reason"] : "0";
        string markdown = cast(string) test["markdown"];
        string expected = cast(string) test["html"];

        if (section == "Emphasis and strong emphasis" && expected.count('_') == 0)
            markdown = markdown.replace("_", "*");

        markdown = markdown.replaceCodeBlockDelimiters(section);
        expected = expected.replaceCodeBlockDelimiters(section).escapeMarkdownChars().replaceNewlines();

        ddoc.write("$(EXPLANATION ", exampleNumber, ",");
        if (expectFailure)
        {
            ddoc.write(" This test is [expected to fail](#fail_reason_", failReason, ")");
            if (exclude)
                ddoc.write(" and has been excluded because it breaks rendering");
        }
        else
            ddoc.write(" Error generating HTML from Markdown");
        ddoc.write(".)\n");

        string escapedMarkdown = markdown.escapeMarkdownChars().replaceNewlines().replace("\"", "&quot;");
        ddoc.write("<input id=\"markdown-", exampleNumber, "\" type=\"hidden\" value=\"", escapedMarkdown, "\"></input>\n");
        ddoc.write("<div class=\"markdown code-block\"><strong>Markdown</strong><pre><code id=\"markdown-code-", exampleNumber, "\"></code></pre></div>\n");

        if (!exclude)
        {
            ddoc.write("$(MARKDOWN_TEST ");
            ddoc.write(test["example"]);
            ddoc.write(",\n");
            ddoc.write(markdown);
            ddoc.write(")\n");

            ddoc.write("$(EXPECTED_RESULT ");
            ddoc.write(test["example"]);
            ddoc.write(", ");
            ddoc.write(failReason);
            ddoc.write(",\n");
            ddoc.write(expected);
            ddoc.write(")\n");
        }
        ddoc.write("+/\n");

		specJSON.skipOver(",");
		specJSON.stripLeft();
	}

    ddoc.write(`/++
<a name="fail_reasons"></a>
## Reasons for expected failures
`);
    foreach (i, reason; failureReasons)
    {
        ddoc.write((i+1), `. <a name="fail_reason_`, (i+1), `"></a> `, reason, `
`);
    }

	ddoc.write("This page was generated by https://github.com/dgileadi/ddoc-commonmark-spec from [the CommonMark spec version ", specVersion, "](http://spec.commonmark.org/", specVersion, "/).");
    ddoc.write(r"
+/
module ddocmarkdown;
");
}

private string replaceCodeBlockDelimiters(string markdown, string section)
{
    bool atLineStart = true;
    size_t breakStart = -1;
    size_t breakEnd = -1;
    char breakType = 0;

    void replaceBreak()
    {
        char replacement = breakType == '*' || section.startsWith("Thematic") ? '_' : '*';
        size_t length = breakEnd - breakStart;
        if (breakStart != -1 && (length >= 3 || (breakType == '*' && length == 2)))
            for (size_t i = breakStart; i < breakEnd; i++)
                if (markdown[i] == breakType)
                    markdown.replaceInPlace(i, i + 1, to!string(replacement));
    }

    for (size_t i = 0; i < markdown.length; i++)
    {
        char c = markdown[i];
        switch (c)
        {
            case '\n':
                replaceBreak();
                breakStart = -1;
                breakEnd = -1;
                atLineStart = true;
                break;
            case ' ':
            case '\t':
                break;
            case '-':
            case '*':
                if (atLineStart && breakStart == -1)
                {
                    breakType = c;
                    breakStart = i;
                }
                if (breakType == c)
                    breakEnd = i + 1;
                else
                {
                    breakStart = -1;
                    breakEnd = -1;
                }
                atLineStart = false;
                break;
            case '\\':
                if (!atLineStart)
                {
                    breakStart = -1;
                    breakEnd = -1;
                }
                break;
            default:
                atLineStart = false;
                breakStart = -1;
                breakEnd = -1;
                break;
        }
    }
    replaceBreak();
    return markdown;
}

private string replaceNewlines(string s)
{
    return s.replace("\r", "&#13;").replace("\n", "&#10;");
}

private string escapeMarkdownChars(string s)
{
    for (size_t i = 0; i < s.length; i++)
    {
        char c = s[i];
        switch (c)
        {
        case ',':
        case '`':
        case '*':
        case '_':
        case '{':
        case '}':
        case '[':
        case ']':
        case '(':
        case ')':
        case '#':
        case '+':
        case '-':
        case '~':
        case '.':
        case '!':
        case '\\':
            string escaped = "&#" ~ to!string(cast(int)c) ~ ';';
            s.replaceInPlace(i, i + 1, escaped);
            i += escaped.length - 1;
            break;
        default:
            break;
        }
    }
    return s;
}