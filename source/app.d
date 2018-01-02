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
    string specFile = "spec.json";
    if (!exists(specFile))
        download("http://spec.commonmark.org/0.28/spec.json", specFile);

    auto ignoreJSON = toJSONValue("ignore.json".readText());
    string[] ignoreReasons = getReasons(ignoreJSON);
    JSONValue[string] ignoreExamples = cast(JSONValue[string]) ignoreJSON["examples"];
    auto ddoc = File("ddoc-commonmark-spec.d", "w");
    ddoc.write(r"// PERMUTE_ARGS:
// REQUIRED_ARGS: -D -Dd${RESULTS_DIR}/compilable -o-
// POST_SCRIPT: compilable/extra-files/ddocAny-postscript.sh markdown
// EXTRA_SOURCES: extra-files/commonmark-spec.ddoc

/++
Tests for DDoc's limited support of the CommonMark spec

Spec Examples:
");

    auto specJSON = specFile.readText();
	specJSON.strip();
	specJSON.skipOver("[");

	while (specJSON.length > 1)
	{
		auto test = specJSON.parseJSONValue();
        string exampleNumber = cast(string) test["example"];

		ddoc.write("\n$(EXAMPLE_HEADER ", exampleNumber, ", ", test["section"], ")\n");

        bool ignore = (exampleNumber in ignoreExamples) !is null;
        bool exclude = ignore && cast(bool) ignoreExamples[exampleNumber]["exclude"];
        string failReason = ignore ? cast(string) ignoreExamples[exampleNumber]["reason"] : "0";
        string markdown = cast(string) test["markdown"];

        ddoc.write("$(EXPLANATION ", exampleNumber, ",");
        if (ignore)
        {
            ddoc.write(" This test is [expected to fail](#fail_reason_", failReason, ")");
            if (exclude)
                ddoc.write(" and has been excluded because it also fails to compile");
        }
        else
            ddoc.write(" Error generating HTML from Markdown");
        ddoc.write(".)\n");

        if (!exclude)
        {
            ddoc.write("<input id=\"markdown-", exampleNumber, "\" type=\"hidden\" value=\"", markdown, "\"></input>\n");
            ddoc.write("<div class=\"markdown code-block\"><strong>Markdown</strong><pre><code id=\"markdown-code-", exampleNumber, "\"></code></pre></div>\n");

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
            ddoc.write(test["html"]);
            ddoc.write(")\n\n");
        }

		specJSON.skipOver(",");
		specJSON.stripLeft();
	}

	ddoc.write(r"
+/
module ddocmarkdown;
");
}

string[] getReasons(JSONValue ignore) {
    JSONValue[] ignoreReasons = cast(JSONValue[]) ignore["reasons"];
    string[] reasons = new string[ignoreReasons.length];
    foreach (i, reason; ignoreReasons)
        reasons[i] = cast(string) reason;
    return reasons;
}
