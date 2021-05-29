import vibe.core.stream;
import vibe.stream.operations;
import vibe.internal.allocator;
import vibe.utils.string;
import vibe.utils.dictionarylist;

import std.exception;

alias InetHeaderMap = DictionaryList!(string, false, 12);
void parseHeader(InputStream)(InputStream input, ref InetHeaderMap dst, bool initial=false, size_t max_line_length = 1000, IAllocator alloc = vibeThreadAllocator(), bool rfc822_compatible = true)
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
			enforce(colonpos >= 0, "Header is missing ':'.");
			enforce(colonpos > 0, "Header name is empty.");
			hdr = ln[0..colonpos].stripA();
			hdrvalue = ln[colonpos+1..$].stripA();
			if(initial && hdr.toLower=="content-type")
				break;
		} else {
			hdrvalue ~= " " ~ ln.stripA();
		}
	}
	addPreviousHeader();
}
