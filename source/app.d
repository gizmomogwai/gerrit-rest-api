/++
 + Copyright: Copyright (c) 2021, Christian Koestlin
 + License: MIT
 + Authors: Christian Koestlin
 +/

import std;
import requests;
import colored;
import mir.ion.deser.json;
import std.parallelism;
import asciitable;

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

struct UserWithServers
{
    User user;
    Server[] servers;
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

string stateForUserAsString(Server[] servers, string user)
{
    // dfmt off
    return servers
        .map!(server => getServerState(server, user))
        .map!((server) {
            auto result = "%s:%s".format(server.nickName, server.openIssues);
            return (server.openIssues == 0 ? result.green : result.red).to!string;
        })
        .join(" | ")
    ;
    // dfmt on
}

auto stateForUserAsArray(Server[] servers, string user)
{
    // dfmt off
    return servers
        .map!(server => getServerState(server, user).openIssues.to!string.rightJustify(6))
        .map!(server => (server == "0" ? server.green : server.red).to!string)
    ;
    // dfmt on
}

void main(string[] args)
{
    auto executable = args[0];

    auto configFile = args[1];
    auto command = args[2];
    auto config = deserializeJson!(Config)(configFile.readText);
    auto servers = config.servers;
    auto users = config.users;
    auto usersWithServers = users.map!(user => UserWithServers(user, servers)).array;
    switch (command)
    {
    case "review":
        auto user = args[3];
        servers.stateForUserAsString(user).writeln;
        break;
    case "open":
        auto user = args[3];
        foreach (server; servers.map!(server => getServerState(server, user)))
        {
            if (server.openIssues > 0)
            {
                auto url = "%s/q/status:open+owner:%s".format(server.url, user);
                std.process.execute(["open", url]);
            }
        }
        break;
    case "list":
        // dfmt off
        // workaround for double-context problem see: https://forum.dlang.org/post/elstswbwhpvrfnsqeirp@forum.dlang.org
        static fn = (UserWithServers u) => [u.user.nickName].chain(u.servers.stateForUserAsArray(u.user.userName)).array;
        auto data = taskPool
            .amap!(fn)(usersWithServers)
            .sort!((a, b) => a < b);

        new AsciiTable(servers.length + 1)
            .header.add(" ").reduce!((head, server) => head.add(server.nickName.rightJustify(6)))(servers)
            .table
            .reduce!((table, user) => table.row.reduce!((row, v) => row.add(v))(user).table)(data)
            .format
            .parts(new UnicodeParts)
            .headerSeparator(true)
            .columnSeparator(true)
            .writeln;
        // dfmt on
        break;
    default:
        usage(executable);
        break;
    }
}
