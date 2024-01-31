/++
 + Copyright: Copyright (c) 2021, Christian Koestlin
 + License: MIT
 + Authors: Christian Koestlin
 +/

import asciitable : AsciiTable, UnicodeParts;
import colored : green, red;
import mir.deser.json : deserializeJson;
import mir.serde : serdeIgnore;
import packageinfo : packages;
import requests : BasicAuthentication, queryParams, Request;
import std.algorithm : filter, fold, map, reduce, sort;
import std.array : array, join;
import std.conv : to;
import std.file : readText;
import std.json : parseJSON;
import std.parallelism : parallel;
import std.process : execute;
import std.range : chain;
import std.stdio : stderr, writeln;
import std.string : format, rightJustify, strip;
struct Config
{
    Server[] servers;
    User[] users;
}

string mapNickNameToUserName(User[] users, string nickName) {
    auto result = users.filter!(user => user.nickName == nickName).map!(user => user.userName);
    if (result.empty) {
        throw new Exception("Cannot find nickname '%s' in configuration".format(nickName).red.to!string);
    }
    return result.front;
}

struct User
{
    /// Name as it appears in the "UI".
    string nickName;
    /// Name as used by lookup on the servers.
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
        .map!(server => (server.strip == "0" ? server.green : server.red).to!string)
    ;
    // dfmt on
}

int main(string[] args)
{
    auto executable = args[0];

    auto configFile = args[1];
    auto command = args[2];
    auto config = deserializeJson!(Config)(configFile.readText);
    auto servers = config.servers;
    auto users = config.users;
    switch (command)
    {
    case "version":
        import asciitable;
        import colored;
        import packageinfo;

        // dfmt off
        auto table = packages
            .sort!("a.name < b.name")
            .fold!((table, p) =>
                   table
                   .row
                   .add(p.name.white)
                   .add(p.semVer.lightGray)
                   .add(p.license.lightGray).table)
            (new AsciiTable(3)
             .header
             .add("Package".bold)
             .add("Version".bold)
             .add("License".bold).table);
        // dfmt on
        stderr.writeln("Packageinfo:\n", table.format.prefix("    ")
                       .headerSeparator(true).columnSeparator(true).to!string);
        break;
    case "review":
        auto nickName = args[3];
        auto user = users.mapNickNameToUserName(nickName);
        servers.stateForUserAsString(user).writeln;
        break;
    case "open":
        auto nickName = args[3];
        auto user = users.mapNickNameToUserName(nickName);
        foreach (server; servers.map!(server => getServerState(server, user)))
        {
            if (server.openIssues > 0)
            {
                auto url = "%s/q/status:open+owner:%s".format(server.url, user);
                ["open", url].execute();
            }
        }
        break;
    case "list":
        // dfmt off
        auto result = new string[][users.length];
        foreach (i, user; users.parallel)
        {
            result[i] = [user.nickName].chain(servers.stateForUserAsArray(user.userName)).array;
        }
        result.sort!((a, b) => a[0] < b[0]);

        new AsciiTable(servers.length + 1)
            .header.add(" ").reduce!((head, server) => head.add(server.nickName.rightJustify(6)))(servers)
            .table
            .reduce!((table, user) => table.row.reduce!((row, v) => row.add(v))(user).table)(result)
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
    return 0;
}
