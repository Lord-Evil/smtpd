import std.stdio;
import std.conv:to, parse;
import std.string;
import std.functional;
import core.time;

import vibe.data.json;
import vibe.core.core : runApplication, exitEventLoop, disableDefaultSignalHandlers, setTimer, lowerPrivileges;
import vibe.core.net;
import vibe.http.client;
static import std.file;
import mailParser: parseMail;

protected string serverHost;
protected string forwardTo;
TCPListener listener;
TCPConnection[] sessions;

alias void function(int) sighandler_t;
extern (C) sighandler_t signal(int signum, sighandler_t handler);

void shutDown(int i){
	writeln("\nSignal caught! "~i.to!string~"\nShutting down!");
	foreach(TCPConnection s; sessions){
		s.write("\nShutting down!\nBye!\n");
		s.close();
	}
	listener.stopListening();
	//судя по всему, все эти клоузы и стопы это отложенные задачи, и если стопарнуть ивент луп сразу, то они не успеют отработать, нужно, чтобы "петля" прошла хотябы раз
	//потому используем новую задачу "таймер", чтобы завершить работу всего
	setTimer(1.seconds, (){
		exitEventLoop();
	}, true);
}

int main(string[] args){
	Json config = parseJsonString(cast(string)std.file.read("config.json"));
	serverHost = config["host"].get!string;
	forwardTo = config["forward"].get!string;

	disableDefaultSignalHandlers();
	signal(2,&shutDown);
	signal(15,&shutDown);
	listener = listenTCP(config["port"].get!ushort, toDelegate(&handleConn), config["bind"].get!string);
	try{
		string user = config["user"].get!string;
		string group = config["group"].get!string;
		lowerPrivileges(user, group);	
	}catch(Exception e){}
	
	return runApplication();
}
@trusted nothrow void handleConn(TCPConnection stream){
	try{
		writeln("Incomming connection from "~stream.remoteAddress.to!string);
		sessions~=stream;
		SmtpSession session = new SmtpSession(stream);
		while(stream.connected){
			string line;
			while(stream.waitForData)
			{
				ubyte[1] buf;
				stream.read(buf);
				if(buf[0] == '\r')continue;
				if(buf[0] == '\n')break;
				line~=buf;
			}
			if(line.length){
				session.handleLine(line);
			}
		}
		if(session.mailBody.length>0){
			writeln("Mail body size:"~session.mailBody.length.to!string);
			//writeln(session.mailBody);
			setTimer(1.seconds, (){
				requestHTTP(forwardTo,
				(scope req){
					req.method = HTTPMethod.POST;
					req.writeJsonBody(session.container);
				},
				(scope res){
					
				});

			});
		}
		sessions.removeFromArray(stream);
		stream.close();
		writeln("Peer disconnected "~stream.remoteAddress.to!string);
	}catch(Exception){
		assert("Something went wrong!");
	}
}
class SmtpSession
{
	protected string mailBody;
private:
	enum State{
		Helo,
		From,
		To,
		Data,
		ReadData,
		End
	}
	TCPConnection _s;
	string from;
	string to;
	string sender;
	State state;
	void reply(string msg, string code){
		_s.write(code~" "~msg~"\n");
	}
	void ok(string code = "250"){
		reply("+OK", code);
	}
	void bad(){
		reply("+Err","500");
	}
	bool handleFrom(string line){
		if(line.length>10&&line[0..9].toLower == "mail from"){
			if(line[9] == ':'){
				string[] mf = line[10..$].strip.split("@");
				if(mf.length == 2&&mf[0].length>0&&mf[1].length>0){
					if(mf[1][mf[1].length-1] == '>')mf[1]=mf[1][0..$-1];
					if(mf[0][0] == '<')mf[0]=mf[0][1..$];
					from = mf[0].stripLeft~"@"~mf[1].stripRight;
					return true;
				}
			}		
		}
		return false;
	}
	bool handleTo(string line){
		if(line.length>8&&line[0..7].toLower == "rcpt to"){
			if(line[7] == ':'){
				string[] mt = line[8..$].strip.split("@");
				if(mt.length == 2&&mt[0].length>0&&mt[1].length>0){
					if(mt[1][mt[1].length-1] == '>')mt[1]=mt[1][0..$-1];
					if(mt[0][0] == '<')mt[0]=mt[0][1..$];
					if(mt[1] == serverHost){
						to = mt[0].strip();
						return true;
					}
				}
			}		
		}
		return false;
	}
public:
	this(TCPConnection stream){
		_s = stream;
		reply(serverHost,"220");
	}
	void handleLine(string line){
		switch(state){
			case State.Helo:
				if(line.length>5&&line[0..4].toLower == "helo"){
					sender = line[5..$];
					writeln("Sender: "~sender);
					state = State.From;
					ok();
					return;
				}
				break;
			case State.From:
				if(handleFrom(line)){
					writeln("Mail from: "~from);
					state = State.To;
					reply(from~" accepted","250");
					return;
				}
				break;
			case State.To:
				if(handleTo(line)){
					writeln("Mail to: "~to);
					state = State.Data;
					reply(to~"@"~serverHost~" ok","250");
					return;
				}
				break;
			case State.Data:
				if(line.strip.toLower == "data"){
					writeln("Accepting data");
					reply("finish with \".\" on a single line","354");
					state = State.ReadData;
					return;
				}
				break;
			case State.ReadData:
				if(line == "."){
					state = State.End;
					reply("Accepted","250");
					reply("Bye!","221");
					_s.close();
					return;
				}
				mailBody~=line~'\n';
				return;
			default:break;
		}
		if(line.toLower == "quit"||line.toLower == "bye"){
			_s.close();
			return;
		}
		writeln("Did not understand: "~line);
		bad();
	}
	Json container(){
		Json data = Json.emptyObject;
		data["from"]=from;
		data["to"]=to;
		data["body"]=parseMail(mailBody);
		return data;
	}
}

void removeFromArray(T)(ref T[] array, T item)
{
	foreach( i; 0 .. array.length )
		if( array[i] is item ){
			removeFromArrayIdx(array, i);
			return;
		}
}

void removeFromArrayIdx(T)(ref T[] array, size_t idx)
{
	foreach( j; idx+1 .. array.length)
		array[j-1] = array[j];
	array.length = array.length-1;
}
