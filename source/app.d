/++
 + Copyright: Copyright (c) 2021, Christian Koestlin
 + License: MIT
 + Authors: Christian Koestlin
 +/

import std;
import requests;
import colored;
import mir.ion.deser.json;

struct Config
{
    Server[] servers;
    User[] users;
}

struct User
{
    string nickName;
    string userName;
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
    request.verbosity = 0;
    auto p = queryParams("q", "status:open owner:%s".format(user));
    auto response = request.get("%s/a/changes/".format(server.url), p);
    auto responseString = response.responseBody.to!string;
    // see https://gerrit-review.googlesource.com/Documentation/rest-api.html#output why stripping is needed
    auto json = parseJSON(responseString[5 .. $ - 1]);
    server.openIssues = json.array.length;
    return server;
}

void usage(string executable)
{
    throw new Exception("Usage: %s config (review username|open user|list)".format(executable));
}

string stateForUser(Server[] servers, string user)
{
    return servers.map!(server => getServerState(server, user))
        .map!((server) {
            auto result = "%s:%s".format(server.nickName, server.openIssues);
            return (server.openIssues == 0 ? result.green : result.red).to!string;
        })
        .join(" | ");
}

void main(string[] args)
{
    auto executable = args[0];

    auto configFile = args[1];
    auto command = args[2];
    auto config = deserializeJson!(Config)(configFile.readText);
    auto servers = config.servers;
    auto users = config.users;
    switch (command)
    {
    case "review":
        auto user = args[3];
        writeln(servers.stateForUser(user));
        break;
    case "open":
        auto user = args[3];
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
    case "list":
        foreach (user; users)
        {
            writeln(user.nickName, ": ", servers.stateForUser(user.userName));
        }
        break;
    default:
        usage(executable);
        break;
    }
}
