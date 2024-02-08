/++
 + Copyright: Copyright (c) 2021, Christian Koestlin
 + License: MIT
 + Authors: Christian Koestlin
 +/

import argparse;
import asciitable : AsciiTable, UnicodeParts;
import colored : bold, green, lightGray, red, white, blue;
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

string mapNickNameToUserName(User[] users, string nickName)
{
    auto result = users.filter!(user => user.nickName == nickName)
        .map!(user => user.userName);
    if (result.empty)
    {
        throw new Exception("Cannot find nickname '%s' in configuration".format(nickName)
                .red.to!string);
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
            return Arguments.withColors ? (server.openIssues == 0 ? result.green : result.red).to!string : result;
        })
        .join(" | ")
    ;
    // dfmt on
}

auto stateForUserAsArray(Server[] servers, string user, bool colors)
{
    // dfmt off
    return servers
        .map!(server => getServerState(server, user).openIssues.to!string.rightJustify(6))
        .map!(server => colors ? (server.strip == "0" ? server.green : server.red).to!string : server)
    ;
    // dfmt on
}

@(Command("list"))
struct List
{
}

@(Command("review"))
struct Review
{
    string nickName;
}

@(Command("open"))
struct Open
{
    string nickName;
}


auto color(T)(string s, T color)
{
    writeln(Arguments.withColors ? "true" : "false", " for ", s);
    return Arguments.withColors ? color(s).to!string : s;
}

//dfmt off
@(Command(null)
  .Epilog(() => "PackageInfo:\n" ~ packages
                        .sort!("a.name < b.name")
                        .fold!((table, p) =>
                               table
                               .row
                                   .add(p.name.color(&white))
                                   .add(p.semVer.color(&lightGray))
                                   .add(p.license.color(&lightGray)).table)
                            (new AsciiTable(3)
                                .header
                                    .add("Package".color(&bold))
                                    .add("Version".color(&bold))
                                    .add("License".color(&bold)).table)
                        .format
                            .prefix("    ")
                            .headerSeparator(true)
                            .columnSeparator(true)
                        .to!string))
// dfmt on
struct Arguments
{
    @ArgumentGroup("Common arguments")
    {
        @(NamedArgument("withColors", "c"))
        static auto withColors = ansiStylingArgument;
        @(NamedArgument("config").Placeholder("CONFIG").Required())
        string config;
    }
    SubCommand!(Default!List, Review, Open) command;
}

int main_(Arguments arguments)
{
    auto config = deserializeJson!(Config)(arguments.config.readText);
    auto servers = config.servers;
    auto users = config.users;
    return arguments.command.match!((List list) {
        // dfmt off
        auto result = new string[][users.length];
        bool colors = Arguments.withColors ? true : false;
        foreach (i, user; users.parallel)
        {
            result[i] = [user.nickName].chain(servers.stateForUserAsArray(user.userName, colors)).array;
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
            .writeln
        ;
        // dfmt on
        return 0;
        }, (Review review) {
        auto user = users.mapNickNameToUserName(review.nickName);
        servers.stateForUserAsString(user).writeln;
        return 0;
    }, (Open open) {
        auto user = users.mapNickNameToUserName(open.nickName);
        foreach (server; servers.map!(server => getServerState(server, user)))
        {
            if (server.openIssues > 0)
            {
                auto url = "%s/q/status:open+owner:%s".format(server.url, user);
                ["open", url].execute();
            }
        }
        return 0;
    },
    );
}

mixin CLI!(Arguments).main!((arguments) { return main_(arguments); });
