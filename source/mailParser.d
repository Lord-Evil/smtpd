import std.stdio;
import vibe.inet.message;
import vibe.stream.memory;
import vibe.inet.message: decodeMessage, decodeEmailAddressHeader;
import vibe.data.json;
import std.string;
import std.array;

import headerParser;

Json parseMail(string email)
{
	ubyte[] hdr = cast(ubyte[])email.dup;
	InetHeaderMap map;
	parseHeader(createMemoryStream(hdr), map);
	Json result = Json.emptyObject;
	Json headers = Json.emptyObject;

	foreach(string key, string val; map.byKeyValue){
		//writeln(key,": ",val);
		key=key.toLower();
		if(key == "to" || key == "from"){
			string name;
			string address;
			decodeEmailAddressHeader(val, name, address);
			Json addressField = Json.emptyObject;
			addressField["name"]=name;
			addressField["address"]=address;
			headers[key]=addressField;
		}else if(key=="content-type"){
			headers[key]=parseContentType(val);
		}else{
			headers[key]=val;
		}
	}
	result["headers"]=headers;
	//writeln(headers);
	if(headers["content-type"].type!=Json.Type.undefined){
		if(headers["content-type"]["type"]=="text/plain"){
			string body = parseBody(email);
			result["body"]=body;
			if(headers["content-transfer-encoding"].type!=Json.Type.undefined){
				result["body"] = decodeBody(body, headers["content-transfer-encoding"].get!string);
			}
			//writeln("\nPlain Body:");
			//writeln(body);
		}else if(headers["content-type"]["type"]=="multipart/alternative" || headers["content-type"]["type"]=="multipart/mixed"){
			if(headers["content-type"]["boundary"].type!=Json.Type.undefined){
				result["body"]=Json.emptyArray;
				result["inlines"]=Json.emptyArray;
				result["attachments"]=Json.emptyArray;
				//writeln(email);
				//writeln("Boundary: '"~headers["content-type"]["boundary"].get!string~"'");
				string[] contentParts = parseMultipart(email, headers["content-type"]["boundary"].get!string);
				//writeln(contentParts);
				for(int i=0; i<contentParts.length; i++){
					Json part = Json.emptyObject;
					ubyte[] parthdr = cast(ubyte[])contentParts[i].dup;
					InetHeaderMap partmap;
					parseHeader(createMemoryStream(parthdr), partmap);
					//writeln(partmap);
					foreach(string key, string val; partmap.byKeyValue){
						key=key.toLower();
						if(key=="content-type"){
							part["content-type"]=parseContentType(val);
						}else if(key=="content-disposition"){
							part["content-disposition"]=parseContentType(val);
						}else{
							part[key]=val;
						}
					}
					if(part["content-type"].type!=Json.Type.undefined){
						if(part["content-type"]["type"]=="text/plain" || part["content-type"]["type"]=="text/html"){
							part["content"]=parseBody(contentParts[i]);
							if(part["content-transfer-encoding"].type!=Json.Type.undefined){
								part["content"] = decodeBody(part["content"].get!string, part["content-transfer-encoding"].get!string);
							}
							result["body"]~=part;
						}else{
							if(part["content-disposition"]["type"]=="attachment"){
								part["content"]=parseBody(contentParts[i]);
								if(part["content-transfer-encoding"].type!=Json.Type.undefined){
									part["content"] = decodeBody(part["content"].get!string, part["content-transfer-encoding"].get!string);
								}
								result["attachments"]~=part;
							}else if(part["content-disposition"]["type"]=="inline"){
								part["content"]=parseBody(contentParts[i]);
								if(part["content-transfer-encoding"].type!=Json.Type.undefined){
									part["content"] = decodeBody(part["content"].get!string, part["content-transfer-encoding"].get!string);
								}
								result["inlines"]~=part;
							}
						}
					}
				}
			}
		}else{
			writeln("Unknown Content-Type: ", headers["content-type"]);
		}
	}else{
		result["body"]=parseBody(email);
		if(!result["body"].length)
			writeln("Message contains no body");
	}
	return result;
}
string decodeBody(string content, string transferEncoding){
	if(transferEncoding=="base64"){
		return content.replace('\n', "");
	}else if(transferEncoding=="quoted-printable"){
		return decodeMessage(cast(ubyte[])content.dup, "quoted-printable");
	}else{
		writeln("Unknown Content-Transfer-Encoding: ", transferEncoding);
	}
	return content;
}
Json parseContentType(string val){
	Json contentType = Json.emptyObject;
	string[] parts = val.split(';');
	contentType["type"]=parts[0].strip();
	for(int i=1;i<parts.length;i++){
        parts[i] = parts[i].replace('"',"").strip();
        long eqIdx = parts[i].indexOf("=");
		string key = parts[i][0..eqIdx];
        string pval = parts[i][eqIdx+1..$];
		contentType[key]=pval;
	}
	return contentType;
}

string parseBody(string data){
	bool newLine = false;
	for(int i; i<data.length; i++){
		if(data[i]=='\n'){
			if(newLine){
				return data[i..$].strip;
			}else{
				newLine = true;
			}
		}else{
			newLine = false;
		}
	}
	return "";
}


string[] parseMultipart(string data, string boundary){
	string[] parts;
	long idx=0;
	while(true){
		long start = data.indexOf("--"~boundary, idx)+boundary.length+3;
		long end = data.indexOf("--"~boundary, start);
		if(end<0) return parts;
		idx=end;
		if(end<start){
			writeln("Bad data:", start, end);
			data.writeln;
		}
		parts~=data[start..end];
	}
}