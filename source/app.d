import std;
import requests;
import colored;
import mir.ion.deser.json;

struct Config
{
    Server[] servers;
}

struct Server
{
    string nickName;
    string url;
    string userName;
    string password;

    @serdeIgnore ulong openIssues;
}

Server getServerState(Server server, string user)
{
    auto request = new Request;
    request.authenticator = new BasicAuthentication(server.userName, server.password);
    auto p = queryParams("q", "status:open owner:%s".format(user));
    auto response = request.get("%s/a/changes/".format(server.url), p);
    auto responseString = response.responseBody.toString;
    auto json = parseJSON(responseString[5 .. $ - 1]);
    server.openIssues = json.array.length;
    return server;
}

void usage(string executable)
{
    throw new Exception(
            "Usage: %s config (review|open) username".format(executable));
}

void main(string[] args)
{
    auto executable = args[0];
    if (args.length != 4)
    {
        usage(executable);
    }

    auto config = args[1];
    auto command = args[2];
    auto user = args[3];
    auto servers = deserializeJson!(Config)(config.readText).servers;
    switch (command)
    {
    case "review":
        writeln(servers.map!(server => getServerState(server, user))
                .map!((server) {
                    auto result = "%s:%s".format(server.nickName, server.openIssues);
                    return (server.openIssues == 0 ? result.green : result.red).to!string;
                })
                .join(" | "));
        break;
    case "open":
        foreach (server; servers.map!(server => getServerState(server, user)))
        {
            if (server.openIssues > 0)
            {
                auto url = "%s/q/status:open+owner:%s".format(server.url, user);
                writeln("open ", url);
                std.process.execute(["open", url]);
            }
        }
        break;
    default:
        usage(executable);
        break;
    }
}
