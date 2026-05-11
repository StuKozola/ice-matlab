classdef HtmlUnescapeTest < matlab.unittest.TestCase

    methods (Test)
        function namedEntities(tc)
            tc.verifyEqual(ice.util.htmlUnescape("AT&amp;T"), "AT&T");
            tc.verifyEqual(ice.util.htmlUnescape("&quot;hi&quot;"), """hi""");
            tc.verifyEqual(ice.util.htmlUnescape("a&lt;b&gt;c"), "a<b>c");
        end

        function decimalNumeric(tc)
            tc.verifyEqual(ice.util.htmlUnescape("caf&#233;"), "café");
        end

        function hexNumeric(tc)
            tc.verifyEqual(ice.util.htmlUnescape("caf&#xe9;"), "café");
        end

        function preservesPlainText(tc)
            tc.verifyEqual(ice.util.htmlUnescape("plain text"), "plain text");
        end
    end
end
