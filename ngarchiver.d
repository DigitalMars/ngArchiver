/* Program to convert newsgroup postings to html files.
 */


/* Better formatting:
 * http://thread.gmane.org/gmane.comp.version-control.git/57643/focus=57918
 */

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.ctype;

import std.uri;
import std.file;
import std.stdio;
import std.string;
import std.conv;
import std.format;
import std.array;
import std.utf;

import undead.date;

version=READPHP;

immutable stylesheet = "http://www.digitalmars.com/forum.css";
immutable printsheet = "http://www.digitalmars.com/forum-print.css";

// Do not write html files from before this date
immutable pivotdate = "Jan 1, 2012";



class Posting
{
    string filename;
    string filebody;
    string[] lines;
    string from;
    string date;
    string[] msg;
    string subject;
    string newsgroups;
    string[] refs;
    Posting[] replies;	// Postings that reply to this
    string boundary;
    string msgid;
    Posting L,R,U,D;
    int nmessages = 1;	// number of messages in this thread
    int counted;
    int written;
    int tocwritten;
    d_time pdate;	// date[] converted to time_t
    d_time most_recent_date;	// time of most recent reply
    string shortdate;	// date[] converted to canonical, short form

    this(string filename)
    {
	this.filename = filename;
    }
}

File[int] indexfiles;	// index files, key type is the year

int[string] msgid2num;	// from message id to message number

Posting[] postings;

int main(string[] args)
{
    auto year = undead.date.yearFromTime(undead.date.getUTCtime());

    if (args.length != 5)
    {
	writefln("Usage: ngarchiver fromdir todir sitedir ngdir");
	exit(1);
    }

    auto fromdir = args[1];
    auto todir = args[2];
    auto sitedir = args[3];
    auto ngdir = args[4];

    auto fromdirng = std.path.buildPath(fromdir, ngdir);
    string todirng;
    string sitedirng;
    if (ngdir == "D")
    {	todirng = todir;
	sitedirng = sitedir;
    }
    else
    {   todirng = std.path.buildPath(todir, ngdir);
	sitedirng = std.path.buildPath(sitedir, ngdir);
    }

    writefln("fromdirng = %s", fromdirng);
    writefln("todirng   = %s", todirng);
    writefln("sitedirng = %s", sitedirng);

    writefln("Getting file names...");

    // Get all the files in directory fromdirng into files[]
    string[] files = listdir(fromdirng);

    writefln("%s files", files.length);

    // Determine which of the files in files[] are postings,
    // and put them in postings[]
    postings.length = files.length;
  Lfiles:
    foreach (filename; files)
    {
	// Posting filenames are simply numbers, incremented sequentially
	if (filename.length > 8)
	    continue;			// more than 99,999,999 articles? No way
	if (filename.length > 0 && filename.length == '0')
	    continue;			// no leading '0' in filename
	foreach (c; filename)
	{
	    if (!core.stdc.ctype.isdigit(c))
		continue Lfiles;
	}
	auto n = atoi(filename);
	if (toString(n) != filename)
	    continue;

	if (n >= postings.length)
	    postings.length = n + 1;
	postings[n] = new Posting(filename);
    }

    writefln("Reading postings...");

    string newsgroup;
    foreach (size_t n, Posting posting; postings)
    {
	if (!posting)
	    continue;
	std.stdio.writef("%s\r", posting.filename);
	posting.filebody = cast(string)std.file.read(std.path.buildPath(fromdirng, posting.filename));
	if (posting.filebody.length == 0)
	    continue;
	posting.lines = splitlines(posting.filebody);
	if (posting.lines.length == 0)
	    continue;

	// Parse the file
	foreach (size_t i, string line; posting.lines)
	{
	    if (std.string.indexOf(line, "From: ") == 0)
		posting.from = line[6 .. line.length];

	    if (std.string.indexOf(line, "Date: ") == 0)
	    {	posting.date = line[6 .. line.length];
		posting.pdate = undead.date.parse(posting.date);
		posting.most_recent_date = posting.pdate;
		posting.shortdate = undead.date.toDateString(posting.pdate)[4 .. $];
		if (year == undead.date.yearFromTime(posting.pdate))
		    posting.shortdate = posting.shortdate[0 .. $ - 5];
	    }

	    if (std.string.indexOf(line, "Subject: ") == 0)
		posting.subject = line[9 .. line.length];

	    if (std.string.indexOf(line, "Newsgroups: ") == 0)
	    {	posting.newsgroups = line[12 .. line.length];
		// If more than one, pick first one
		auto j = std.string.indexOf(posting.newsgroups, ',');
		if (j > 0)
		    posting.newsgroups = posting.newsgroups[0 .. j];
		if (!newsgroup && j <= 0)
		    newsgroup = posting.newsgroups;
	    }

	    if (std.string.indexOf(line, "Message-ID: ") == 0)
	    {	posting.msgid = line[12 .. line.length];
		msgid2num[posting.msgid] = cast(int)n;
	    }

	    if (std.string.indexOf(line, "References: ") == 0)
	    {	string refs = line[12 .. line.length];
		posting.refs = std.string.split(refs);
		// Might be continued on next line(s)
		for (auto j = i + 1; j < posting.lines.length; ++j)
		{
		    auto rline = posting.lines[j];
		    if (rline.length > 2 &&
			(rline[0] == ' ' || rline[0] == '\t'))
		    {
			posting.refs ~= std.string.split(rline[1 .. $]);
		    }
		    else
		        break;
		}
	    }

	    auto b = std.string.indexOf(line, "boundary=");
	    if (b >= 0)
	    {	b += 9;		// skip over 'boundary='
		if (line[b] == '"')
		{
		    ++b;
		    auto e = std.string.indexOf(line[b .. line.length], '"');
		    if (e >= 0)
			posting.boundary = line[b .. b + e];
		}
		else
		    posting.boundary = line[b .. $];
	    }

	    if (line.length == 0)
	    {
		posting.msg = posting.lines[i + 1 .. posting.lines.length];
		break;
	    }
	}

	if (posting.refs.length == 0 &&
	    std.string.indexOf(posting.subject, "Re: ") == 0)
	{
	    /* It's a reply, but there are no references.
	     * Try to find its antecedent.
	     */
	    //writefln("\n%s %s", n, posting.subject);
	    for (size_t m = n; m--; )
	    {
		auto p = postings[m];
		if (p && p.subject == posting.subject[4 .. $])
		{
		    posting.refs = new string[1];
		    posting.refs[0] = p.msgid;
		    //writefln("    found it %s", m);
		    break;
		}
	    }
	}

	version (none)
	{
	    writefln("from: %s", posting.from);
	    foreach (string line; posting.msg)
	    {
		writefln("--> %s", line);
	    }
	}

	extractMsg(posting, posting.msg);
    }

    // Fill in replies[]
    foreach (Posting posting; postings)
    {
	if (!posting)
	    continue;
	int mostrecent = 0;
	foreach (rf; posting.refs)
	{
	    auto pn = rf in msgid2num;
	    if (pn && *pn > mostrecent)
		mostrecent = *pn;
	}
	auto p = postings[mostrecent];
	if (p)
	{
	    p.replies ~= posting;
	}
    }

    writefln("Writing HTML files...");

    auto fpindex = File(std.path.buildPath(todirng, "index.html"), "w");
    header(fpindex, "news.digitalmars.com - " ~ newsgroup, null, null, null, null);
    indexfiles[year] = fpindex;

    auto fpftp = File(std.path.buildPath(todirng, "put.ftp"), "w");
    version(none)
    {
	fpftp.writeln("name");
	fpftp.writeln("password");
	fpftp.writeln("bin");
    }
    fpftp.writefln("cd %s", sitedirng);
    fpftp.writefln("put index.html");

    static pivot = d_time_nan;
    if (pivot == d_time_nan)
    {
	pivot = undead.date.parse(pivotdate);
    }

    string prev;	// previous thread filename
    string next;	// next thread filename

    string prevTitle;
    string nextTitle;

    for (size_t i = postings.length; i--;)
    {
	//printf("posting[%d]\n", i);
	Posting posting = postings[i];

	if (!posting)
	    continue;
	if (posting.refs.length == 0)		// if posting is start of a thread
	{
	    // Find [next] posting
	    next = null;
	    for (size_t j = i; j--;)
	    {
		Posting posting2 = postings[j];

		if (posting2 && posting2.refs.length == 0)
		{
		    next = toHtmlFilename(posting2);
		    nextTitle = posting2.subject;
		    break;
		} 
	    }

	    string fname = toHtmlFilename(posting);

	    posting.nmessages = 1 + countReplies(posting);

	    if (posting.most_recent_date > pivot)
	    {	// Write out the html file
		auto fp = File(std.path.buildPath(todirng, fname), "w");
		header(fp, posting.newsgroups ~ " - " ~ posting.subject, prev, next, prevTitle, nextTitle);
		if (!posting.tocwritten)
		{
		    fp.writefln("<div id=\"PostingTOC\">");
		    fp.writefln("<ul>");
		    toTOC(fp, posting, 0);
		    fp.writefln("</ul>");
		    fp.writefln("</div>");
		}
		toHTML(fp, posting, posting);
		google(fp);
		footer(fp);
		fp.close();
	    }

	    prev = fname;
	    prevTitle = posting.subject;

	    if (posting.most_recent_date > pivot)
		fpftp.writefln("put %s", fname);	// append to put.ftp

	    // Determine year of posting
	    int pyear = year;
	    if (postings.length > 1000)
		// if lots of posts, split into years
		pyear = undead.date.yearFromTime(posting.most_recent_date);
	    if (!(pyear in indexfiles))
	    {	// Create new index file
		string indexfilename = std.string.format("index%d.html", pyear);
		fpindex = File(std.path.buildPath(todirng, indexfilename), "w");
		header(fpindex, "news.digitalmars.com - " ~ newsgroup, null, null, null, null);
		indexfiles[pyear] = fpindex;
		fpftp.writefln("put %s", indexfilename);
	    }

	    // Add posting to index file
	    fpindex = indexfiles[pyear];
	    fpindex.writefln("<tt>%s</tt> &nbsp;&nbsp;", posting.shortdate);
	    fpindex.writefln("<a href=\"%s\">", fname);
	    escapeHTML(fpindex, posting.subject);
	    fpindex.writefln("</a>&nbsp;<small>(%s)</small><br>\n", posting.nmessages);
	}
    }
    writefln("done writing html");

    fpftp.writefln("bye");
    fpftp.close();

    int[] years = indexfiles.keys;
    years.sort;
    foreach (y1, fp; indexfiles)
    {
	fp.writefln("<br>Other years:<br>");
	foreach_reverse (y; years)
	{
	    if (y1 == y)
		fp.writefln("%s ", y);
	    else if (y == year)
	    {
		fp.writefln("<a href=\"index.html\">%s</a> ", y);
	    }
	    else
	    {
		fp.writefln("<a href=\"index%s.html\">%s</a> ", y, y);
	    }
	}

	google(fp);
	footer(fp);
	fp.close();
    }

    writefln("Done");
    return 0;
}

/*******************************
 * Transitively count up all the replies to p.
 */
int countReplies(Posting p)
{
    assert(p);
    if (p.counted)
	return 0;
    p.counted = 1;

    //writefln("counting ", p.filename);

    // Count all replies
    int n = cast(int)p.replies.length;
    foreach (reply; p.replies)
    {
	n += countReplies(reply);
    }
    return n;
}

/*******************************
 * Write p to table of contents
 */
void toTOC(ref File fp, Posting p,int depth)
{
    assert(p);
    if (p.tocwritten)
	return;
    p.tocwritten = 1;

    //writefln("TOC Writing ", p.filename);

    try
    {
	fp.writefln("<li>");
	fp.writefln("<a href=\"#N%s\">", p.filename);

	/* Strip "" and email address from p.from
	 */
	auto from = p.from;
	if (from.length > 4)
	{
	    if (from[0] == '"')
	    {
		auto i = lastIndexOf(from, '"');
		if (i > 1)
		    from = from[1 .. i];
	    }
	    else if (from[$ - 1] == '>')
	    {
		auto i = indexOf(from, '<');
		if (i > 0)
		{
		    if (from[i - 1] == ' ')
			--i;
		    from = from[0 .. i];
		}
	    }
	}
	escapeHTML(fp, from);

	fp.writefln("</a>");

	int totalLines, quotedLines;
	auto firstline = messageStats(p.msg, totalLines, quotedLines);
	fp.writefln(" (%d/%d)", totalLines - quotedLines, totalLines);

	fp.writefln(" %s", p.shortdate);

	if (firstline.length > 30)
	    firstline = firstline[0 .. 30];
	fp.writefln(" <small>%s...</small>", firstline);

	fp.writeln("</li>");
    }
    catch (Exception o)
    {
	writefln("error writing posting %s %s", p.filename, o);
    }

    // Append all replies
    bool ol;
    Posting U;

    foreach (posting; p.replies)
    {
	if (posting.tocwritten)
	    continue;
	if (!ol)
	{   ol = true;
	    fp.writefln("<ul>");
	}
	if (!p.R)
	    p.R = posting;
	posting.L = p;
	posting.U = U;
	toTOC(fp, posting, depth + 1);
	if (U)
	    U.D = posting;
	U = posting;
    }

    if (ol)
	fp.writefln("</ul>");
}

/***************************************
 * Write out p and all its descendents to fp.
 *
 * Params:
 *	pstart = posting that is the start of this thread
 */

void toHTML(ref File fp, Posting p, Posting pstart)
{
    assert(p);
    if (p.written)
	return;
    p.written = 1;

    //writefln("Writing ", p.filename);

    try
    {
	fp.writef( `<div id="Posting">`);
	scope (success)	fp.writef( "</div>");

	{
	fp.writef( "<div id=\"PostingHeading\">");
	scope (success) fp.writefln("</div>");

	fp.writef( `<a name="N%s">`, p.filename);
	scope (success) fp.writef( "</a>");

	if (p.U)
	    fp.writef( "<a href=\"#N%s\"><img src=\"http://www.digitalmars.com/blue-up.png\" border=0 alt=\"prev sibling\"></a> ", p.U.filename);
	else
	    fp.writef( "<img src=\"http://www.digitalmars.com/grey-up.png\" border=0> ");

	if (p.D)
	    fp.writef( "<a href=\"#N%s\"><img src=\"http://www.digitalmars.com/blue-down.png\" border=0 alt=\"next sibling\"></a> ", p.D.filename);
	    //fp.writef( "<a href=\"#N%s\">&darr;</a> ", p.D.filename);
	else
	    fp.writef( "<img src=\"http://www.digitalmars.com/grey-down.png\" border=0> ");

	if (p.L)
	    fp.writef( "<a href=\"#N%s\"><img src=\"http://www.digitalmars.com/blue-left.png\" border=0 alt=\"parent\"></a> ", p.L.filename);
	else
	    fp.writef( "<img src=\"http://www.digitalmars.com/grey-left.png\" border=0> ");

	if (p.R)
	    fp.writef( "<a href=\"#N%s\"><img src=\"http://www.digitalmars.com/blue-right.png\" border=0 alt=\"reply\"></a> ", p.R.filename);
	else
	    fp.writef( "<img src=\"http://www.digitalmars.com/grey-right.png\" border=0> ");

	escapeHTML(fp, p.from);

	version (READPHP)
	{
	    fp.writef(
	       " <a href=\"http://www.digitalmars.com/pnews/read.php?server=news.digitalmars.com&group=%s&artnum=%s%s",
		p.newsgroups,
		p.filename,
		"\"> writes</a>:");
	}
	else
	{
	    fp.writef(
		" <a href=\"http://www.digitalmars.com/drn-bin/wwwnews?%s/%s%s",
		std.uri.encodeComponent(p.newsgroups),
		p.filename,
		"\"> writes</a>:");
	}
	}

	{
	fp.writefln(`<pre class="PostingBody">`);
	scope (success) fp.writefln("</pre>");

	void writeQuote(size_t first, size_t last)
	{
	    // Remove leading blank lines
	    while (first <= last)
	    {
		if (p.msg[first].length)
		    break;
		first++;
	    }
	    // Remove trailing blank lines
	    while (first <= last)
	    {
		if (p.msg[last].length)
		    break;
		last--;
	    }
	    if (first > last)
		return;
	    bool quote = false;
	    int quotefirst;
	    int quotelast;
	    foreach (i, ref line; p.msg[first .. last + 1])
	    {
		if (line.length && line[0] == '>')
		{
		    if (!quote)
		    {   quote = true;
			quotefirst = cast(int)i;
		    }
		    line = line[1 .. $];
		}
		else if (line.length >= 2 && line[0] == ' ' && line[1] == '>')
		{
		    if (!quote)
		    {   quote = true;
			quotefirst = cast(int)i;
		    }
		    line = line[2 .. $];
		}
		else
		{
		    if (quote)
		    {
			fp.writefln("<pre class=\"PostingQuote\">");
			writeQuote(first + quotefirst, first + i - 1);
			fp.writefln("</pre><br>");
			quote = false;
		    }
		    auto line2 = line;
		    while (line2.length > 80)
		    {	// Wrap long lines
			auto j = std.string.lastIndexOf(line2[0..80], ' ');
			if (j < 20)
			{
			    j = std.string.indexOf(line2[20..$], ' ');
			    if (j == -1 || j == line2.length - 1)
				break;
			}
			writeLine(fp, line2[0 .. j]);
			fp.writefln("");
			line2 = line2[j + 1 .. $];
		    }
		    writeLine(fp, line2);
		    fp.writefln("");
		}
	    }
	    if (quote)
	    {
		fp.writefln("<pre class=\"PostingQuote\">");
		writeQuote(quotefirst + first, last);
		fp.writefln("</pre><br>");
	    }
	}

	if (p.msg.length)
	    writeQuote(0, p.msg.length - 1);
	}

	fp.writef( `<div id="PostingFooting">`);
	  fp.writefln(" %s", p.shortdate);
	fp.writefln("</div>");
    }
    catch (Exception o)
    {
	writefln("error writing posting %s %s", p.filename, o);
    }

    // Append all replies
    foreach (posting; p.replies)
    {
	if (posting.written)
	    continue;

	toHTML(fp, posting, pstart);
	d_time t = undead.date.parse(posting.date);
	if (t > pstart.most_recent_date)
	    pstart.most_recent_date = t;
    }
}

/*******************************
 * Rewrites msg[] to be subset of lines
 * that form the message body.
 */
void extractMsg(Posting p, ref string[] msg)
{
    if (!msg.length)
	return;
    int first = int.max;
    int last = -1;
    if (p.boundary.length)
    {   // Only do the first section
	int state;

	foreach (int i, string line; msg)
	{
	    if (line.length > 2 && line[2 .. line.length] == p.boundary)
	    {   if (state)
		    break;
		state++;
	    }
	    else if (state)
	    {
		if (i < first)
		    first = i;
		if (i > last)
		    last = i;
	    }
	}
    }
    else
    {
	foreach (int i, string line; msg)
	{
	    // Look for 'begin OOO filename', and ignore it
	    if (line.length > 9 &&
		line[0 .. 6] == "begin " &&
		isdigit(line[6]))
	    {
		if (first == int.max)
		{
		    msg = msg[0 .. 0];
		    return;
		}
	    }
	    if (i < first)
		first = i;
	    if (i > last)
		last = i;
	}
    }
    foreach (i; first .. last + 1)
    {
	string line = msg[i];
	if (std.string.indexOf(line, "Content-Type: ") == 0)
	    ++first;
	else if (std.string.indexOf(line, "Content-Transfer-Encoding: ") == 0)
	    ++first;
	else
	    break;
    }
    msg = msg[first .. last + 1];
}

/*****************************************
 * Get message stats.
 */
string messageStats(string[] msg, out int totalLines, out int quotedLines)
{
    string firstline;
    foreach (line; msg)
    {
	if (line.length == 0)
	    continue;
	++totalLines;
	if (line[0] == '>' ||
	    (line.length > 1 && line[0] == ' ' && line[1] == '>'))
	{
	    if (line[0] == '>' && line.length > 1 ||
		line.length > 2)
	    {
		++quotedLines;
		if (totalLines - quotedLines <= 2)
		    firstline = null;
	    }
	    else
		--totalLines;	// blank line, do not count it
	}
	else if (!firstline)
	    firstline = line;
    }
    assert(quotedLines <= totalLines);
    assert(totalLines <= msg.length);
    return firstline;
}

void header(ref File fp, string title, string prev, string next, string prevTitle, string nextTitle)
{
    if (prevTitle.length == 0)
	prevTitle = "previous topic";

    if (prevTitle.length == 0)
	prevTitle = "next topic";

    fp.writefln(`
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html lang="en-US">
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8" />
<title>`);

    escapeHTML(fp, title);

    fp.writefln(`
</title>
<link rel="stylesheet" type="text/css" href="%s" />
<link rel="stylesheet" type="text/css" href="%s" media="print" />
</head>

<body>
<div id="heading">
<a href="http://www.digitalmars.com/"><img src="http://www.digitalmars.com/dmlogo.gif" BORDER=0 WIDTH=270 HEIGHT=53 ALT="www.digitalmars.com"></a>

  <a href="http://www.digitalmars.com/" title="Digital Mars"><img src="http://www.digitalmars.com/home.png" border=0></a>
&nbsp; <a href="http://www.digitalmars.com/advancedsearch.html" title="Search Digital Mars web site"><img src="http://www.digitalmars.com/search.png" border=0></a>
&nbsp; <a href="http://www.digitalmars.com/NewsGroup.html" title="News Groups"><img src="http://www.digitalmars.com/news.png" border=0></a>
&nbsp; <a href="http://www.digitalmars.com/d/" title="D Programming Language"><img src="http://www.digitalmars.com/d.png" border=0></a>
&nbsp; <a href="http://www.digitalmars.com/download/freecompiler.html" title="C/C++ compilers">C &amp; C++</a>
&nbsp; <a href="http://www.digitalmars.com/dscript/" title="DMDScript">DMDScript</a>
`, stylesheet, printsheet);

    if (prev || next)
    {
	fp.writefln("&nbsp;<a href=\"index.html\" title=\"topic index\"><img src=\"http://www.digitalmars.com/blue-index.png\" border=0></a>");

	if (prev)
	{   fp.writef( `<a href="%s" title="`, prev);
	    escapeHTML(fp, prevTitle);
	    fp.writefln(`"><img src="http://www.digitalmars.com/blue-left.png" border=0></a>`);
	}
	else
	    fp.writefln("<img src=\"http://www.digitalmars.com/grey-left.png\" border=0>");

	if (next)
	{   fp.writef( `<a href="%s" title="`, next);
	    escapeHTML(fp, nextTitle);
	    fp.writefln(`"><img src="http://www.digitalmars.com/blue-right.png" border=0></a>`);
	}
	else
	    fp.writefln("<img src=\"http://www.digitalmars.com/grey-right.png\" border=0>");
    }

    fp.writefln("%s", `
</div>
<div id="navigation">

<div class="navblock">
<form method="get" action="http://www.google.com/search">
<div style="text-align:center">
<input id="q" name="q" size="10" value="Search" onFocus='if(this.value == "Search"){this.value="";}'>
<input type="hidden" id="domains" name="domains" value="www.digitalmars.com">
<input type="hidden" id="sitesearch" name="sitesearch" value="www.digitalmars.com/d/archives">
<input type="hidden" id="sourceid" name="sourceid" value="google-search">
<input type="submit" id="submit" name="submit" value="Go">
</div>
</form>
</div>

<div class="navblock">
<h2>D Programming</h2>
<ul>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D">digitalmars.D</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/announce">digitalmars.D.announce</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/learn">digitalmars.D.learn</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/ldc">digitalmars.D.ldc</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/bugs">digitalmars.D.bugs</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/dtl">digitalmars.D.dtl</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/ide">digitalmars.D.ide</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/debugger">digitalmars.D.debugger</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/dwt">digitalmars.D.dwt</a></li>
<li><a href="http://www.digitalmars.com/d/archives/D/gnu">D.gnu</a></li>
<li><a href="http://www.digitalmars.com/d/archives/">D</a></li>
</ul>
</div>

<div class="navblock">
<h2>C/C++ Programming</h2>
<ul>
<li><a href="http://www.digitalmars.com/d/archives/c++">c++</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/announce">c++.announce</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/atl">c++.atl</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/beta">c++.beta</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/chat">c++.chat</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/command-line">c++.command-line</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/dos">c++.dos</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/dos/16-bits">c++.dos.16-bits</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/dos/32-bits">c++.dos.32-bits</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/idde">c++.idde</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/mfc">c++.mfc</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/rtl">c++.rtl</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/stl">c++.stl</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/stl/hp">c++.stl.hp</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/stl/port">c++.stl.port</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/stl/sgi">c++.stl.sgi</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/stlsoft">c++.stlsoft</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/windows">c++.windows</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/windows/16-bits">c++.windows.16-bits</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/windows/32-bits">c++.windows.32-bits</a></li>
<li><a href="http://www.digitalmars.com/d/archives/c++/wxwindows">c++.wxwindows</a></li>
</ul>
</div>

<div class="navblock">
<h2>Other</h2>
<ul>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/empire">digitalmars.empire</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/DMDScript">digitalmars.DMDScript</a></li>
<li><a href="http://www.digitalmars.com/d/archives/electronics">electronics</a></li>
</ul>
</div>

<div class="navblock">
<script type="text/javascript"><!--
google_ad_client = "pub-5628673096434613";
google_ad_width = 120;
google_ad_height = 90;
google_ad_format = "120x90_0ads_al_s";
google_ad_channel ="7651800615";
google_color_border = "336699";
google_color_bg = "C6C8EB";
google_color_link = "0000FF";
google_color_url = "008000";
google_color_text = "000000";
//--></script>
<script type="text/javascript" src="http://pagead2.googlesyndication.com/pagead/show_ads.js">
</script>

<hr>
<script src="http://www.gmodules.com/ig/ifr?url=http://www.google.com/ig/modules/translatemypage.xml&up_source_language=en&w=160&h=60&title=&border=&output=js"></script>
</div>

</div>
<div id="sidebar">
<!-- Google ad -->
<script type="text/javascript"><!--
google_ad_client = "pub-5628673096434613";
google_ad_width = 120;
google_ad_height = 600;
google_ad_format = "120x600_as";
google_ad_channel ="7651800615";
google_page_url = document.location;
//--></script>
<script type="text/javascript"
  src="http://pagead2.googlesyndication.com/pagead/show_ads.js">
</script>
</div>
<div id="content">
`);

    fp.writef( "<h2>");
    escapeHTML(fp, title);
    fp.writefln("</h2>");
}

void footer(ref File fp)
{
    fp.writefln("</div></BODY></HTML>");
}

void google(ref File fp)
{
    fp.writef( "%s", `
<div id="footer_ad">
<br><br><br><br>
<center>
<script type="text/javascript"><!--
google_ad_client = "pub-5628673096434613";
google_ad_width = 300;
google_ad_height = 250;
google_ad_format = "300x250_as";
google_ad_type = "text_image";
google_ad_channel ="7651800615";
google_color_border = "336699";
google_color_bg = "FFFFFF";
google_color_link = "0000FF";
google_color_url = "008000";
google_color_text = "000000";
//--></script>
<script type="text/javascript" src="http://pagead2.googlesyndication.com/pagead/show_ads.js">
</script>

<!--
<br>
<br>
<SCRIPT charset="utf-8" type="text/javascript" src="http://ws.amazon.com/widgets/q?ServiceVersion=20070822&MarketPlace=US&ID=V20070822/US/classicempire/8006/adfa749b-6f27-4cdf-a046-716a8fab7cab"> </SCRIPT> <NOSCRIPT><A HREF="http://ws.amazon.com/widgets/q?ServiceVersion=20070822&MarketPlace=US&ID=V20070822%2FUS%2Fclassicempire%2F8006%2Fadfa749b-6f27-4cdf-a046-716a8fab7cab&Operation=NoScript">Amazon.com Widgets</A></NOSCRIPT>
-->

</center>
</div>
`);

}

void escapeHTML(ref File fp, string s)
{
    // Note: replace "Mark Evans" with "Mark E."

    foreach (char c; s)
    {
	switch (c)
	{
	    case '<':
		fp.write("&lt;");
		break;

	    case '>':
		fp.write("&gt;");
		break;

	    case '&':
		fp.write("&amp;");
		break;

	    case '@':
		fp.write(" ");
		break;

	    default:
		fp.write(c);
		break;
	}
    }
}

/*************************************
 * Write line of posting text to output.
 */

void writeLine(ref File fp, string line)
{
    auto i = std.string.indexOf(line, 'h', CaseSensitive.no);
    if (i == -1)
	goto L1;

    //if (line[i + 1] == 't') writefln("found h '%s'", line[i .. length]);
    string url;
    url = isURL(line[i .. $]);
    if (!url)
    {	escapeHTML(fp, line[0 .. i + 1]);
	writeLine(fp, line[i + 1 .. $]);
	return;
    }

    //writefln("found url '%s'", url);
    escapeHTML(fp, line[0 .. i]);
    string rest = line[i + url.length .. $];

    // Convert url from old wwwnews format to new format
    static string wwwnews = "http://www.digitalmars.com/drn-bin/wwwnews?";
    if (url.length > wwwnews.length && std.string.cmp(url[0 .. wwwnews.length], wwwnews) == 0)
    {
	auto j = std.string.indexOf(url[wwwnews.length .. $], '/');
	if (j == -1)
	    goto L2;

	string ng = url[wwwnews.length .. wwwnews.length + j];
	static string cpp = "c%2B%2B";
	if (ng.length >= cpp.length && std.string.cmp(ng[0 .. cpp.length], cpp) == 0)
	    ng = "c++" ~ ng[cpp.length .. $];

	string article = url[wwwnews.length + j + 1 .. $];

	url = "http://www.digitalmars.com/pnews/read.php?server=news.digitalmars.com&group="
	      ~ ng
	      ~ "&artnum="
	      ~ article;
	fp.writef( `<a href="%s">%s/%s</a>`, url, ng, article);
	goto L3;
    }

L2:
    // Make url into clickable link
    fp.writef( `<a href="%s">%s</a>`, url, url);
L3:
    writeLine(fp, rest);
    return;

L1:
    escapeHTML(fp, line);
}

/**************************
 * Recognize email address
 * References:
 *	RFC2822
 */

string isEmail(string s)
{   size_t i;

    if (!isalpha(s[0]))
	return null;;

    for (i = 1; 1; i++)
    {
	if (i == s.length)
	    return null;
	auto c = s[i];
	if (isalnum(c))
	    continue;
	if (c == '-' || c == '_' || c == '.')
	    continue;
	if (c != '@')
	    return null;
	i++;
	break;
    }
    //writefln("test1 '%s'", s[0 .. i]);

    /* Now do the part past the '@'
     */
    size_t lastdot;
    for (; i < s.length; i++)
    {
	auto c = s[i];
	if (isalnum(c))
	    continue;
	if (c == '-' || c == '_')
	    continue;
	if (c == '.')
	{
	    lastdot = i;
	    continue;
	}
	break;
    }
    if (!lastdot || (i - lastdot != 3 && i - lastdot != 4))
	return null;

    return s[0 .. i];
}


/***************************
 * Recognize URL
 */

string isURL(string s)
{
    /* Must start with one of:
     *	http://
     *	https://
     *	www.
     */

    size_t i;

    if (s.length <= 4)
	return null;

    //writefln("isURL(%s)", s);
    if (s.length > 7 && std.string.icmp(s[0 .. 7], "http://") == 0)
	i = 7;
    else if (s.length > 8 && std.string.icmp(s[0 .. 8], "https://") == 0)
	i = 8;
//    if (icmp(s[0 .. 4], "www.") == 0)
//	i = 4;
    else
	return null;

    size_t lastdot;
    for (; i < s.length; i++)
    {
	auto c = s[i];
	if (isalnum(c))
	    continue;
	if (c == '-' || c == '_' || c == '?' ||
	    c == '=' || c == '%' || c == '&' ||
	    c == '/' || c == '+' || c == '#' ||
	    c == '~')
	    continue;
	if (c == '.')
	{
	    lastdot = i;
	    continue;
	}
	break;
    }
    //if (!lastdot || (i - lastdot != 3 && i - lastdot != 4))
    if (!lastdot)
	return null;

    return s[0 .. i];
}

string toHtmlFilename(Posting p)
{
    char[] fname = null;
    static d_time pivot = d_time_nan;
    static d_time pivot2 = d_time_nan;

    if (pivot == d_time_nan)
    {
	pivot = undead.date.parse("September 18, 2006");
	pivot2 = undead.date.parse("December 17, 2006");
    }

    if (p.pdate < pivot)
	// Keep old way for link compatibility
	fname ~= p.filename ~ ".html";
    else
    {
	fname = p.subject.dup;
	if (fname.length && fname[0] == '-')
	    fname[0] = '_';		// no leading -
	foreach (ref c; fname)
	{
	    if (!isalnum(c) && c != '.' && c != '-')
		c = '_';
	}
	if (p.pdate > pivot2 && fname.length > 100)
	    fname.length = 100;
	fname ~= '_' ~ p.filename ~ ".html";
	fname = std.string.squeeze(fname, "_");
	if (fname[0] == '_' && isalnum(fname[1]))
	    fname = fname[1 .. $];
    }
    return cast(string)fname;
}

/*********************************
 * Convert string to integer.
 */

long atoi(const(char)[] s)
{
    return core.stdc.stdlib.atoi(toStringz(s));
}

char[] toString(ulong u)
{   char[ulong.sizeof * 3] buffer;
    int ndigits;
    char[] result;

    ndigits = 0;
    while (u)
    {
        char c = cast(char)((u % 10) + '0');
        u /= 10;
        ndigits++;
        buffer[buffer.length - ndigits] = c;
    }
    result = new char[ndigits];
    result[] = buffer[buffer.length - ndigits .. buffer.length];
    return result;
}

string[] listdir(string pathname)
{
    import std.file;
    import std.path;
    import std.algorithm;
    import std.array;

    string[] files = std.file.dirEntries(pathname, SpanMode.shallow)
        .filter!(a => a.isFile)
        .map!(a => std.path.baseName(a.name))
        .array;

    return files;
}

/**************************************
 * Split s[] into an array of lines,
 * using CR, LF, or CR-LF as the delimiter.
 * The delimiter is not included in the line.
 */

string[] splitlines(string s)
{
    size_t i;
    size_t istart;
    size_t nlines;
    string[] lines;

    nlines = 0;
    for (i = 0; i < s.length; i++)
    {
        auto c = s[i];
        if (c == '\r' || c == '\n')
        {
            nlines++;
            istart = i + 1;
            if (c == '\r' && i + 1 < s.length && s[i + 1] == '\n')
            {
                i++;
                istart++;
            }
        }
    }
    if (istart != i)
        nlines++;

    lines = new string[nlines];
    nlines = 0;
    istart = 0;
    for (i = 0; i < s.length; i++)
    {
        auto c = s[i];
        if (c == '\r' || c == '\n')
        {
            lines[nlines] = s[istart .. i];
            nlines++;
            istart = i + 1;
            if (c == '\r' && i + 1 < s.length && s[i + 1] == '\n')
            {
                i++;
                istart++;
            }
        }
    }
    if (istart != i)
    {   lines[nlines] = s[istart .. i];
        nlines++;
    }

    assert(nlines == lines.length);
    return lines;
}

