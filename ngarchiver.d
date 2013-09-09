/* Program to convert newsgroup postings to html files.
 */


/* Better formatting:
 * http://thread.gmane.org/gmane.comp.version-control.git/57643/focus=57918
 */

import std.uri;
import std.c.stdio;
import std.c.stdlib;
import std.file;
import std.ctype;
import std.stdio;
import std.date;
import std.string;

version=READPHP;

const char[] stylesheet = "http://www.digitalmars.com/forum.css";
const char[] printsheet = "http://www.digitalmars.com/forum-print.css";
//const char[] stylesheet = "style.css";

const char[] pivotdate = "October 1, 2010";
//const char[] pivotdate = "September 1, 2009";
//const char[] pivotdate = "January 1, 2001";




class Posting
{
    char[] filename;
    char[] filebody;
    char[][] lines;
    char[] from;
    char[] date;
    char[][] msg;
    char[] subject;
    char[] newsgroups;
    char[][] refs;
    char[] boundary;
    char[] msgid;
    Posting L,R,U,D;
    int nmessages = 1;	// number of messages in this thread
    int counted;
    int written;
    int tocwritten;
    d_time pdate;	// date[] converted to time_t
    d_time most_recent_date;	// time of most recent reply
    char[] shortdate;	// date[] converted to canonical, short form

    this(char[] filename)
    {
	this.filename = filename;
    }
}

FILE*[int] indexfiles;	// index files, key type is the year

int[char[]] msgid2num;	// from message id to message number

int postingstart;
Posting[] postings;

int main(char[][] args)
{
    char[] ng;
    char[] dir;
    char[] site;
    int year = std.date.YearFromTime(std.date.getUTCtime());

    if (args.length != 3)
    {	writefln("Usage: foo fromdir sitedir");
	exit(1);
    }
    dir = args[1];
    site = args[2];

    writefln("Converting...");

    // Get all the files in directory dir into files[]
    char[][] files = std.file.listdir(dir);

    writefln(files.length, " files");

    // Determine which of the files in files[] are postings,
    // and put them in postings[]
    postings.length = files.length;
  Lfiles:
    foreach (char[] filename; files)
    {
	foreach (char c; filename)
	{
	    if (!std.ctype.isdigit(c))
		continue Lfiles;
	}
	int n = std.string.atoi(filename);
	if (std.string.toString(n) != filename)
	    continue;

	if (n >= postings.length)
	    postings.length = n + 1;
	postings[n] = new Posting(filename);
    }

    writefln("Reading postings...");

    foreach (size_t n, Posting posting; postings)
    {
	if (!posting)
	    continue;
	//writefln("-------------- ", posting.filename, " ------------------");
	posting.filebody = cast(char[])std.file.read(std.path.join(dir, posting.filename));
	posting.lines = std.string.splitlines(posting.filebody);

	// Parse the file
	foreach (size_t i, char[] line; posting.lines)
	{
	    if (std.string.find(line, "From: ") == 0)
		posting.from = line[6 .. line.length];

	    if (std.string.find(line, "Date: ") == 0)
	    {	posting.date = line[6 .. line.length];
		posting.pdate = std.date.parse(posting.date);
		posting.most_recent_date = posting.pdate;
		posting.shortdate = std.date.toDateString(posting.pdate)[4 .. $];
	    }

	    if (std.string.find(line, "Subject: ") == 0)
		posting.subject = line[9 .. line.length];

	    if (std.string.find(line, "Newsgroups: ") == 0)
	    {	posting.newsgroups = line[12 .. line.length];
		// If more than one, pick first one
		int j = std.string.find(posting.newsgroups, ',');
		if (j > 0)
		    posting.newsgroups = posting.newsgroups[0 .. j];
		if (!ng)
		    ng = posting.newsgroups;
	    }

	    if (std.string.find(line, "Message-ID: ") == 0)
	    {	posting.msgid = line[12 .. line.length];
		msgid2num[posting.msgid] = n;
	    }

	    if (std.string.find(line, "References: ") == 0)
	    {	char[] refs = line[12 .. line.length];
		posting.refs = std.string.split(refs);
	    }

	    int b = std.string.find(line, "boundary=\"");
	    if (b >= 0)
	    {	b += 10;		// skip over 'boundary='
		int e = std.string.find(line[b .. line.length], '"');
		if (e >= 0)
		    posting.boundary = line[b .. b + e];
	    }

	    if (line.length == 0)
	    {
		posting.msg = posting.lines[i + 1 .. posting.lines.length];
		break;
	    }
	}

	//printf("from: %.*s\n", posting.from);
	foreach (char[] line; posting.msg)
	{
	    //writefln("--> ", line);
	}
    }

    writefln("Writing HTML files...");

    FILE* fpindex;
    fpindex = std.c.stdio.fopen(toStringz(std.path.join(dir, "index.html")), "w");
    header(fpindex, "news.digitalmars.com - " ~ ng, null, null, null, null);
    indexfiles[year] = fpindex;

    FILE* fpftp;
    fpftp = std.c.stdio.fopen(toStringz(std.path.join(dir, "put.ftp")), "w");
    version(none)
    {
	fwritefln(fpftp, "name");
	fwritefln(fpftp, "password");
	fwritefln(fpftp, "bin");
    }
    fwritefln(fpftp, "cd %s", site);
    fwritefln(fpftp, "put index.html");

    static d_time pivot = d_time_nan;
    if (pivot == d_time_nan)
    {
	pivot = std.date.parse(pivotdate);
    }

    char[] prev;
    char[] next;

    char[] prevTitle;
    char[] nextTitle;

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

	    char[] fname = toHtmlFilename(posting);

	    {
	    int x = postingstart;
	    count(posting, posting, 0);
	    postingstart = x;
	    }

	    if (posting.most_recent_date > pivot)
	    {	// Write out the html file
		auto fp = std.c.stdio.fopen(toStringz(std.path.join(dir, fname)), "w");
		assert(fp);
		header(fp, posting.newsgroups ~ " - " ~ posting.subject, prev, next, prevTitle, nextTitle);
		int x = postingstart;
		if (!posting.tocwritten)
		{
		    fwritefln(fp, "<div id=\"PostingTOC\">");
		    fwritefln(fp, "<ul>");
		    toTOC(fp, posting, posting, 0);
		    fwritefln(fp, "</ul>");
		    fwritefln(fp, "</div>");
		}
		postingstart = x;
		toHTML(fp, posting, posting);
		google(fp);
		footer(fp);
		fclose(fp);
	    }

	    prev = fname;
	    prevTitle = posting.subject;

	    if (posting.most_recent_date > pivot)
		fwritefln(fpftp, "put ", fname);	// append to put.ftp

	    // Determine year of posting
	    int pyear = year;
	    if (postings.length > 1000)
		// if lots of posts, split into years
		pyear = std.date.YearFromTime(posting.most_recent_date);
	    if (!(pyear in indexfiles))
	    {	// Create new index file
		char[] indexfilename = std.string.format("index%d.html", pyear);
		fpindex = std.c.stdio.fopen(toStringz(std.path.join(dir, indexfilename)), "w");
		header(fpindex, "news.digitalmars.com - " ~ ng, null, null, null, null);
		indexfiles[pyear] = fpindex;
		fwritefln(fpftp, "put %s", indexfilename);
	    }

	    // Add posting to index file
	    fpindex = indexfiles[pyear];
	    fwritefln(fpindex, "<tt>%s</tt> &nbsp;&nbsp;", posting.shortdate);
	    fprintf(fpindex, "<a href=\"%.*s\">", fname);
	    escapeHTML(fpindex, posting.subject);
	    fprintf(fpindex, "</a>&nbsp;<small>(%d)</small><br>\n", posting.nmessages);
	}
    }
    writefln("done writing html");

    fwritefln(fpftp, "bye");
    fclose(fpftp);

    int[] years = indexfiles.keys;
    years.sort;
    foreach (y1, fp; indexfiles)
    {
	fwritefln(fp, "<br>Other years:<br>");
	foreach_reverse (y; years)
	{
	    if (y1 == y)
		fwritefln(fp, "%s ", y);
	    else if (y == year)
	    {
		fwritefln(fp, "<a href=\"index.html\">%s</a> ", y);
	    }
	    else
	    {
		fwritefln(fp, "<a href=\"index%s.html\">%s</a> ", y, y);
	    }
	}

	google(fp);
	footer(fp);
	fclose(fp);
    }

    writefln("Done");
    return 0;
}

/*******************************
 */
void count(Posting p, Posting pstart, int depth)
{
    assert(p);
    if (p.counted)
	return;
    p.counted = 1;

    //writefln("counting ", p.filename);

    // Count all replies
    foreach (i, posting; postings[postingstart .. $])
    {
	if (i == postingstart && (!posting || posting.counted))
	    postingstart++;

	if (!posting)
	    continue;

	foreach (rf; posting.refs)
	{   if (rf == p.msgid)
	    {
		if (!posting.counted)
		{
		    count(posting, pstart, depth + 1);
		    pstart.nmessages++;
		}
		break;
	    }
	}
    }
}

/*******************************
 * pstart = start of thread
 */
void toTOC(FILE* fp, Posting p, Posting pstart, int depth)
{
    assert(p);
    if (p.tocwritten)
	return;
    p.tocwritten = 1;

    //writefln("TOC Writing ", p.filename);

    try
    {
	fwritefln(fp, "<li>");
	fwritefln(fp, "<a href=\"#N%s\">", p.filename);
	escapeHTML(fp, p.from);
	fwritefln(fp, "</a>");
	fwritefln(fp, " ", p.shortdate);
	fwritefln(fp, "</li>");
    }
    catch (Object o)
    {
	writefln("error writing posting %s %s", p.filename, o);
    }

    // Append all replies
    bool ol;
    Posting U;
    foreach (size_t i, Posting posting; postings[postingstart .. $])
    {
	if (i == postingstart && (!posting || posting.tocwritten))
	    postingstart++;

	if (!posting)
	    continue;

	foreach (char[] rf; posting.refs)
	{   if (rf == p.msgid)
	    {
		if (!posting.tocwritten)
		{   if (!ol)
		    {	ol = true;
			fwritefln(fp, "<ul>");
		    }
		    if (!p.R)
			p.R = posting;
		    posting.L = p;
		    posting.U = U;
		    toTOC(fp, posting, pstart, depth + 1);
		    if (U)
			U.D = posting;
		    U = posting;
		}
		break;
	    }
	}
    }
    if (ol)
	fwritefln(fp, "</ul>");
}

void toHTML(FILE* fp, Posting p, Posting pstart)
{
    assert(p);
    if (p.written)
	return;
    p.written = 1;

    //writefln("Writing ", p.filename);

    try
    {
	fwritef(fp, `<div id="Posting">`);
	scope (success)	fwritef(fp, "</div>");

	{
	fwritef(fp, "<div id=\"PostingHeading\">");
	scope (success) fwritefln(fp, "</div>");

	fwritef(fp, `<a name="N%s">`, p.filename);
	scope (success) fwritef(fp, "</a>");

	if (p.U)
	    fwritef(fp, "<a href=\"#N%s\"><img src=\"http://www.digitalmars.com/blue-up.png\" border=0 alt=\"prev sibling\"></a> ", p.U.filename);
	else
	    fwritef(fp, "<img src=\"http://www.digitalmars.com/grey-up.png\" border=0> ");

	if (p.D)
	    fwritef(fp, "<a href=\"#N%s\"><img src=\"http://www.digitalmars.com/blue-down.png\" border=0 alt=\"next sibling\"></a> ", p.D.filename);
	    //fwritef(fp, "<a href=\"#N%s\">&darr;</a> ", p.D.filename);
	else
	    fwritef(fp, "<img src=\"http://www.digitalmars.com/grey-down.png\" border=0> ");

	if (p.L)
	    fwritef(fp, "<a href=\"#N%s\"><img src=\"http://www.digitalmars.com/blue-left.png\" border=0 alt=\"parent\"></a> ", p.L.filename);
	else
	    fwritef(fp, "<img src=\"http://www.digitalmars.com/grey-left.png\" border=0> ");

	if (p.R)
	    fwritef(fp, "<a href=\"#N%s\"><img src=\"http://www.digitalmars.com/blue-right.png\" border=0 alt=\"reply\"></a> ", p.R.filename);
	else
	    fwritef(fp, "<img src=\"http://www.digitalmars.com/grey-right.png\" border=0> ");

	escapeHTML(fp, p.from);

	version (READPHP)
	{
	    fwritef(fp,
	       " <a href=\"http://www.digitalmars.com/pnews/read.php?server=news.digitalmars.com&group=%s&artnum=",
		p.newsgroups,
		p.filename,
		"\"> writes</a>:");
	}
	else
	{
	    fwritef(fp,
		" <a href=\"http://www.digitalmars.com/drn-bin/wwwnews?%s/",
		std.uri.encodeComponent(p.newsgroups),
		p.filename,
		"\"> writes</a>:");
	}
	}

	{
	fwritefln(fp, `<pre class="PostingBody">`);
	scope (success) fwritefln(fp, "</pre>");

	int first = int.max;
	int last = -1;
	if (p.boundary.length)
	{   // Only do the first section
	    int state;

	    foreach (int i, char[] line; p.msg)
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
	    foreach (int i, char[] line; p.msg)
	    {
		// Look for 'begin OOO filename', and ignore it
		if (line.length > 9 &&
		    line[0 .. 6] == "begin " &&
		    isdigit(line[6]))
		{
		    break;
		}
		if (i < first)
		    first = i;
		if (i > last)
		    last = i;
	    }
	}

	void writeQuote(int first, int last)
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
	    int quote = 0;
	    int quotefirst;
	    int quotelast;
	    foreach (i, inout line; p.msg[first .. last + 1])
	    {
		if (line.length && line[0] == '>')
		{
		    if (!quote)
		    {   quote = 1;
			quotefirst = i;
		    }
		    line = line[1 .. $];
		}
		else if (line.length >= 2 && line[0] == ' ' && line[1] == '>')
		{
		    if (!quote)
		    {   quote = 1;
			quotefirst = i;
		    }
		    line = line[2 .. $];
		}
		else if (quote)
		{
		    fwritefln(fp, "<pre class=\"PostingQuote\">");
		    writeQuote(first + quotefirst, first + i - 1);
		    fwritefln(fp, "</pre><br>");
		    quote = 0;
		}
		else
		{   auto line2 = line;
		    while (line2.length > 80)
		    {	// Wrap long lines
			auto j = std.string.rfind(line2[0..80], ' ');
			if (j < 20)
			{
			    j = std.string.find(line2[20..$], ' ');
			    if (j == -1 || j == line2.length - 1)
				break;
			}
			writeLine(fp, line2[0 .. j]);
			fwritefln(fp, "");
			line2 = line2[j + 1 .. $];
		    }
		    writeLine(fp, line2);
		    fwritefln(fp, "");
		}
	    }
	    if (quote)
	    {
		fwritefln(fp, "<pre class=\"PostingQuote\">");
		writeQuote(quotefirst + first, last);
		fwritefln(fp, "</pre><br>");
	    }
	}

	writeQuote(first, last);
	}

	fwritef(fp, `<div id="PostingFooting">`);
	  fwritefln(fp, " %s", p.shortdate);
	fwritefln(fp, "</div>");
    }
    catch (Object o)
    {
	writefln("error writing posting %s %s", p.filename, o);
    }

    // Append all replies
    foreach (size_t i, Posting posting; postings[postingstart .. postings.length])
    {
	if (i == postingstart && (!posting || posting.written))
	    postingstart++;

	if (!posting)
	    continue;

	foreach (char[] rf; posting.refs)
	{   if (rf == p.msgid)
	    {	toHTML(fp, posting, pstart);
		d_time t = std.date.parse(posting.date);
		if (t > pstart.most_recent_date)
		    pstart.most_recent_date = t;
		break;
	    }
	}
    }
}

void header(FILE* fp, char[] title, char[] prev, char[] next, char[] prevTitle, char[] nextTitle)
{
    if (prevTitle.length == 0)
	prevTitle = "previous topic";

    if (prevTitle.length == 0)
	prevTitle = "next topic";

    fwritefln(fp, `
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html lang="en-US">
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8" />
<title>`);

    escapeHTML(fp, title);

    fwritefln(fp, `
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
	fwritefln(fp, "&nbsp;<a href=\"index.html\" title=\"topic index\"><img src=\"http://www.digitalmars.com/blue-index.png\" border=0></a>");

	if (prev)
	{   fwritef(fp, `<a href="%s" title="`, prev);
	    escapeHTML(fp, prevTitle);
	    fwritefln(fp, `"><img src="http://www.digitalmars.com/blue-left.png" border=0></a>`);
	}
	else
	    fwritefln(fp, "<img src=\"http://www.digitalmars.com/grey-left.png\" border=0>");

	if (next)
	{   fwritef(fp, `<a href="%s" title="`, next);
	    escapeHTML(fp, nextTitle);
	    fwritefln(fp, `"><img src="http://www.digitalmars.com/blue-right.png" border=0></a>`);
	}
	else
	    fwritefln(fp, "<img src=\"http://www.digitalmars.com/grey-right.png\" border=0>");
    }

    fwritefln(fp, "%s", `
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
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/bugs">digitalmars.D.bugs</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/dtl">digitalmars.D.dtl</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/ide">digitalmars.D.ide</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/dwt">digitalmars.D.dwt</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/announce">digitalmars.D.announce</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/learn">digitalmars.D.learn</a></li>
<li><a href="http://www.digitalmars.com/d/archives/digitalmars/D/debugger">digitalmars.D.debugger</a></li>
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

    fwritef(fp, "<h2>");
    escapeHTML(fp, title);
    fwritefln(fp, "</h2>");
}

void footer(FILE* fp)
{
    fwritefln(fp, "</div></BODY></HTML>");
}

void google(FILE* fp)
{
    fwritef(fp, "%s", `
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

void escapeHTML(FILE* fp, char[] s)
{
    // Note: replace "Mark Evans" with "Mark E."

    foreach (char c; s)
    {
	switch (c)
	{
	    case '<':
		fputs("&lt;", fp);
		break;

	    case '>':
		fputs("&gt;", fp);
		break;

	    case '&':
		fputs("&amp;", fp);
		break;

	    case '@':
		fputs(" ", fp);
		break;

	    default:
		fputc(c, fp);
		break;
	}
    }
}

/*************************************
 * Write line of posting text to output.
 */

void writeLine(FILE* fp, char[] line)
{
    int i;

    i = std.string.ifind(line, 'h');
    if (i == -1)
	goto L1;

    //if (line[i + 1] == 't') writefln("found h '%s'", line[i .. length]);
    char[] url;
    url = isURL(line[i .. length]);
    if (!url)
    {	escapeHTML(fp, line[0 .. i + 1]);
	writeLine(fp, line[i + 1 .. length]);
	return;
    }

    //writefln("found url '%s'", url);
    escapeHTML(fp, line[0 .. i]);
    char[] rest = line[i + url.length .. length];

    // Convert url from old wwwnews format to new format
    static char[] wwwnews = "http://www.digitalmars.com/drn-bin/wwwnews?";
    if (url.length > wwwnews.length && std.string.cmp(url[0 .. wwwnews.length], wwwnews) == 0)
    {
	int j;
	j = std.string.find(url[wwwnews.length .. length], '/');
	if (j == -1)
	    goto L2;

	char[] ng = url[wwwnews.length .. wwwnews.length + j];
	static char[] cpp = "c%2B%2B";
	if (ng.length >= cpp.length && std.string.cmp(ng[0 .. cpp.length], cpp) == 0)
	    ng = "c++" ~ ng[cpp.length .. length];

	char[] article = url[wwwnews.length + j + 1 .. length];

	url = "http://www.digitalmars.com/pnews/read.php?server=news.digitalmars.com&group="
	      ~ ng
	      ~ "&artnum="
	      ~ article;
	fwritef(fp, `<a href="%s">%s/%s</a>`, url, ng, article);
	goto L3;
    }

L2:
    // Make url into clickable link
    fwritef(fp, `<a href="%s">%s</a>`, url, url);
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

char[] isEmail(char[] s)
{   size_t i;

    if (!isalpha(s[0]))
	goto Lno;

    for (i = 1; 1; i++)
    {
	if (i == s.length)
	    goto Lno;
	auto c = s[i];
	if (isalnum(c))
	    continue;
	if (c == '-' || c == '_' || c == '.')
	    continue;
	if (c != '@')
	    goto Lno;
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
	goto Lno;

    return s[0 .. i];

Lno:
    return null;
}


/***************************
 * Recognize URL
 */

char[] isURL(char[] s)
{
    /* Must start with one of:
     *	http://
     *	https://
     *	www.
     */

    size_t i;

    if (s.length <= 4)
	goto Lno;

    //writefln("isURL(%s)", s);
    if (s.length > 7 && std.string.icmp(s[0 .. 7], "http://") == 0)
	i = 7;
    else if (s.length > 8 && std.string.icmp(s[0 .. 8], "https://") == 0)
	i = 8;
//    if (icmp(s[0 .. 4], "www.") == 0)
//	i = 4;
    else
	goto Lno;

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
	goto Lno;

    return s[0 .. i];

Lno:
    return null;
}

char[] toHtmlFilename(Posting p)
{
    char[] fname;
    static d_time pivot = d_time_nan;
    static d_time pivot2 = d_time_nan;

    if (pivot == d_time_nan)
    {
	pivot = std.date.parse("September 18, 2006");
	pivot2 = std.date.parse("December 17, 2006");
    }

    if (p.pdate < pivot)
	// Keep old way for link compatibility
	fname = p.filename ~ ".html";
    else
    {
	fname = p.subject.dup;
	if (fname.length && fname[0] == '-')
	    fname[0] = '_';		// no leading -
	foreach (inout c; fname)
	{
	    if (!isalnum(c) && c != '.' && c != '-')
		c = '_';
	}
	if (p.pdate > pivot2 && fname.length > 100)
	    fname.length = 100;
	fname ~= '_' ~ p.filename ~ ".html";
	fname = std.string.squeeze(fname, "_");
	if (fname[0] == '_' && isalnum(fname[1]))
	    fname = fname[1 .. length];
    }
    return fname;
}
