function out = htmlUnescape(in)
arguments
    in string
end
out = in;
named = ["&amp;", "&"; ...
         "&quot;", """"; ...
         "&apos;", "'"; ...
         "&lt;", "<"; ...
         "&gt;", ">"; ...
         "&nbsp;", " "];
for k = 1:size(named, 1)
    out = replace(out, named(k, 1), named(k, 2));
end
out = regexprep(out, "&#(\d+);", "${char(str2double($1))}");
out = regexprep(out, "&#x([0-9a-fA-F]+);", "${char(hex2dec($1))}");
end
