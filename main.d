module main;

import std.stdio, std.datetime, std.json, std.typecons;
import json;

string testJson1 = `{"a\\next": -544.3, "\\b": "string", "c\\": true,
"d\u005C" : { "a": 10, "b": "test", "c": false },
"e\\e\\e" : [1, 2, 3.5, "str", null], "": null, "\u005c\u005c\u005c" : "unicode"
}`;

string testJson2 = `
{"web-app": {
"servlet": [   
{
    "servlet-name": "cofaxCDS",
        "servlet-class": "org.cofax.cds.CDSServlet",
        "init-param": {
        "configGlossary:installationAt": "Philadelphia, PA",
        "configGlossary:adminEmail": "ksm@pobox.com",
        "configGlossary:poweredBy": "Cofax",
        "configGlossary:poweredByIcon": "/images/cofax.gif",
        "configGlossary:staticPath": "/content/static",
        "templateProcessorClass": "org.cofax.WysiwygTemplate",
        "templateLoaderClass": "org.cofax.FilesTemplateLoader",
        "templatePath": "templates",
        "templateOverridePath": "",
        "defaultListTemplate": "listTemplate.htm",
        "defaultFileTemplate": "articleTemplate.htm",
        "useJSP": false,
        "jspListTemplate": "listTemplate.jsp",
        "jspFileTemplate": "articleTemplate.jsp",
        "cachePackageTagsTrack": 200,
        "cachePackageTagsStore": 200,
        "cachePackageTagsRefresh": 60,
        "cacheTemplatesTrack": 100,
        "cacheTemplatesStore": 50,
        "cacheTemplatesRefresh": 15,
        "cachePagesTrack": 200,
        "cachePagesStore": 100,
        "cachePagesRefresh": 10,
        "cachePagesDirtyRead": 10,
        "searchEngineListTemplate": "forSearchEnginesList.htm",
        "searchEngineFileTemplate": "forSearchEngines.htm",
        "searchEngineRobotsDb": "WEB-INF/robots.db",
        "useDataStore": true,
        "dataStoreClass": "org.cofax.SqlDataStore",
        "redirectionClass": "org.cofax.SqlRedirection",
        "dataStoreName": "cofax",
        "dataStoreDriver": "com.microsoft.jdbc.sqlserver.SQLServerDriver",
        "dataStoreUrl": "jdbc:microsoft:sqlserver://LOCALHOST:1433;DatabaseName=goon",
        "dataStoreUser": "sa",
        "dataStorePassword": "dataStoreTestQuery",
        "dataStoreTestQuery": "SET NOCOUNT ON;select test='test';",
        "dataStoreLogFile": "/usr/local/tomcat/logs/datastore.log",
        "dataStoreInitConns": 10,
        "dataStoreMaxConns": 100,
        "dataStoreConnUsageLimit": 100,
        "dataStoreLogLevel": "debug",
        "maxUrlLength": 500}},
        {
        "servlet-name": "cofaxEmail",
        "servlet-class": "org.cofax.cds.EmailServlet",
        "init-param": {
        "mailHost": "mail1",
        "mailHostOverride": "mail2"}},
        {
        "servlet-name": "cofaxAdmin",
        "servlet-class": "org.cofax.cds.AdminServlet"},

        {
        "servlet-name": "fileServlet",
        "servlet-class": "org.cofax.cds.FileServlet"},
        {
        "servlet-name": "cofaxTools",
        "servlet-class": "org.cofax.cms.CofaxToolsServlet",
        "init-param": {
        "templatePath": "toolstemplates/",
        "log": 1,
        "logLocation": "/usr/local/tomcat/logs/CofaxTools.log",
        "logMaxSize": "",
        "dataLog": 1,
        "dataLogLocation": "/usr/local/tomcat/logs/dataLog.log",
        "dataLogMaxSize": "",
        "removePageCache": "/content/admin/remove?cache=pages&id=",
        "removeTemplateCache": "/content/admin/remove?cache=templates&id=",
        "fileTransferFolder": "/usr/local/tomcat/webapps/content/fileTransferFolder",
        "lookInContext": 1,
        "adminGroupID": 4,
        "betaServer": true}}],
        "servlet-mapping": {
        "cofaxCDS": "/",
        "cofaxEmail": "/cofaxutil/aemail/*",
        "cofaxAdmin": "/admin/*",
        "fileServlet": "/static/*",
        "cofaxTools": "/tools/*"},

        "taglib": {
        "taglib-uri": "cofax.tld",
        "taglib-location": "/WEB-INF/tlds/cofax.tld"}}}
        `;

alias testJson2 testJson;

void main(string[] args)
{
    void myJson()
    {
        auto json = JSONReader!string(testJson);
        auto root = json.value.whole;
    }

    void stdJson()
    {
        auto root = std.json.parseJSON(testJson);
    }

    enum n = 2000;
    auto r = benchmark!(myJson, stdJson)(n);
    auto ms = tuple(r[0].to!("msecs", int)(), r[1].to!("msecs", int)());
    writeln("n = ", n);
    writefln("Milliseconds to call myJson() n times: %s", ms[0]);
    writefln("Milliseconds to call stdJson() n times: %s", ms[1]);
    auto ratio = cast(double)ms[1] / ms[0];
    if (ratio > 1)
        writefln("myJson() is faster than stdJson() %.3sx times", ratio);
    else
        writefln("stdJson() is faster than myJson() %.3sx times", 1 / ratio);
}
