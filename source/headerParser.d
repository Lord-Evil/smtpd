import vibe.core.stream;
import vibe.stream.operations;
import vibe.internal.allocator;
import vibe.utils.string;
import vibe.utils.dictionarylist;
import vibe.inet.message: QuotedPrintable;

import std.exception;

alias InetHeaderMap = DictionaryList!(string, false, 12);
void parseHeader(InputStream)(InputStream input, ref InetHeaderMap dst, size_t max_line_length = 1000, IAllocator alloc = vibeThreadAllocator(), bool rfc822_compatible = true)
	if (isInputStream!InputStream)
{
	string hdr, hdrvalue;

	void addPreviousHeader() {
		if (!hdr.length) return;
		if (rfc822_compatible) {
			if (auto pv = hdr in dst) {
				*pv ~= "," ~ hdrvalue; // RFC822 legacy support
			} else {
				dst[hdr] = hdrvalue;
			}
		} else dst.addField(hdr, hdrvalue);
	}

	string readStringLine() @safe {
		auto ret = input.readLine(max_line_length, "\n", alloc);
		if (ret.length && ret[$-1] == '\r') ret = ret[0..$-1];
		return () @trusted { return cast(string)ret; } ();
	}

	string ln;
	while ((ln = readStringLine()).length > 0) {
		if (ln[0] != ' ' && ln[0] != '\t') {
			addPreviousHeader();

			auto colonpos = ln.indexOf(':');
			enforce(colonpos >= 0, "Header is missing ':'. '"~ln~"'");
			enforce(colonpos > 0, "Header name is empty.");
			hdr = ln[0..colonpos].stripA();
			hdrvalue = ln[colonpos+1..$].stripA();
		} else {
			hdrvalue ~= " " ~ ln.stripA();
		}
	}
	addPreviousHeader();
}

/**
	Decodes a string in encoded-word form.

	See_Also: $(LINK http://tools.ietf.org/html/rfc2047#section-2)
*/
string decodeWords()(string encoded)
{
	import std.array;
	Appender!string dst;
	() @trusted {
		dst = appender!string();
		decodeWords(dst, encoded);
	} ();
	return dst.data;
}
/// ditto
void decodeWords(R)(ref R dst, string encoded)
{
	import std.base64;
	import std.encoding;

	while(!encoded.empty){
		auto idx = encoded.indexOf("=?");
		if( idx >= 0 ){
			auto end = encoded.indexOf("?=");
			enforce(end > idx);
			dst.put(encoded[0 .. idx]);
			auto code = encoded[idx+2 .. end];
			encoded = encoded[end+2 .. $];

			idx = code.indexOf('?');
			auto cs = code[0 .. idx].toLower;
			auto enc = code[idx+1].toLower;
			auto data = code[idx+3 .. $];
			ubyte[] textenc;
			switch(enc){
				default: textenc = cast(ubyte[])data; break;
				case 'b': textenc = Base64.decode(data); break;
				case 'q': textenc = QuotedPrintable.decode(data, true); break;
			}

			switch(cs){
				default: dst.put(sanitizeUTF8(textenc)); break;
				case "utf-8": dst.put(cast(string)textenc); break;
				case "iso-8859-15": // hack...
				case "iso-8859-1":
					string tmp;
					transcode(cast(Latin1String)textenc, tmp);
					dst.put(tmp);
					break;
			}
		} else {
			dst.put(encoded);
			break;
		}
	}
}