#!/usr/bin/perl -w

use utf8;

# We want to output UTF-8
binmode(STDOUT, ':utf8');

# Write pre-amble and root element
open my $out, '>:encoding(utf-8)', 'enytt.xml'
    or die "Unable to write enytt.xml: $!";
print $out qq'<?xml version="1.0" encoding="utf-8"?>\n';
print $out "<etterstad>\n";

# First read all the old articles from arkivet.php; these only have a headline and a link
# (sometimes to somewhere else). They are sorted in reverse chronological order, so read
# them all first and then process
open my $arkiv, '<:encoding(windows-1252):crlf', 'enytt/arkivet.php'
    or die "Unable to open arkivet.php: $!";

my @arkivnyhet;
my %arkivnyhet;

print "Reading arkivet.php\n";
$/ = "\n";
ARCHIVELINE: while (my $line = <$arkiv>)
{
    # Fix broken lines
    $line =~ s/^032\.06\.0/03.06.09/;
    $line =~ s/nyhet(8[3-5][0-9])i.php/nyhet$1.php/;

    # Find lines with article links, internal or external
    if ($line =~ /^ ?([0-9][0-9])\.([0-9][0-9])\.([0-9][0-9]) ?-? ? ?<a href="([^"]+)">(.+)<\/a>/ ||
        $line =~ /^ ?([0-9][0-9])\.([0-9][0-9])\.([0-9][0-9]) ?-? ? ?<a href="([^"]+)"  ?target="_?blank""?>(.*)<\/a>/ ||
        $line =~ /^ ?([0-9][0-9])\.([0-9][0-9])\.([0-9][0-9]) ?-? ? ?<a href="([^"]+)"><\/a>(.*)<br/)
    {
        # Extract metadata
        my $pubdate = "20$3-$2-$1"; # YYYY-MM-DD
        my $shortdate = "20$3$2$1"; # YYYYMMDD for Internet Archive
        my ($url, $title) = ($4, $5);
        #print "Found article $pubdate - $title\n";

        if ($url =~ /http:\/\/www\.etterstad\.no\/(.*php)/)
        {
            # Store internal links directly, dropping link back to domain
            my $php = $1;

            # Drop the history pages; we should import these into a separate section
            if ($php =~ /^historie/)
            {
                next ARCHIVELINE;
            }

            # Some of the stories are linked twice, keep the newest (first) copy
            if (defined $arkivnyhet{$php})
            {
                print "Duplicate link $php at $pubdate (already seen at $arkivnyhet{$php}->{date})\n";
                next ARCHIVELINE;
            }
            unshift(@arkivnyhet, $php);
            $arkivnyhet{$php} = {
                'date' => $pubdate,
                'title' => $title,
            };
        }
        else
        {
            # If this is an external link, assume the link is outdated;
            # point to Internet Archive
            if ($url =~ m@://@)
            {
                $url = "http://web.archive.org/web/${shortdate}000000/$url";
                print "- pointing $pubdate to $url\n";
            }

            # Some of the stories are linked twice, keep the newest (first) copy
            if (defined $arkivnyhet{$url})
            {
                print "Duplicate link $url at $pubdate (already seen at $arkivnyhet{$url}->{date})\n";
                next ARCHIVELINE;
            }
            unshift(@arkivnyhet, $url);
            $arkivnyhet{$url} = {
                'date' => $pubdate,
                'title' => $title,
            };
        }
    }
    else
    {
        # print "Skipping $line";
    }
}
print "Done reading arkivet.php\n\n";
close $arkiv;

# Next import the "current" news page (2018-); these have an entry with some text
# and a link, some to internal articles, some external
open my $index, '<:encoding(windows-1252):crlf', 'enytt/index.php'
    or die "Unable to open arkivet.php: $!";

my @indexnyhet;
my %indexnyhet;

print "Reading index.php\n";
my $inrecord = 0;
$/ = "\n";
INDEXLINE: while (my $line = <$index>)
{
    # Each record start with a START marker and ends with SLUTT
    if ($line =~ /<!-- SLUTT-->/ && $inrecord)
    {
        # Found end of record, output what we have
        if ($headline eq 'Eldre nyheter')
        {
            print "- ignoring '$headline'\n";
            $inrecord = 0;
            next INDEXLINE;
        }

        # A few posts have only a one-line body and no link
        if ($url eq '' &&
            ($headline =~ 'Årsmøte,? Etterstad vel' ||
             $headline eq 'Vann!   Vann!'))
        {
            print "- allowing '$headline' with no link\n";
            $url = 'dummy:' . $pubdate;
        }

        # One story is duplicated in index, keep newest
        if ($url eq 'nyhet1125.php' && defined $indexnyhet{$url})
        {
            print "- ignoring $pubdate $headline ($url already linked}\n";
            $inrecord = 0;
            next INDEXLINE;
        }

        die "No link found for $pubdate $headline\n"
            if $url eq '';
        die "No headline found for $pubdate $url\n"
            if $headline eq '';
        die "No pubdate found for $headline $url\n"
            if $pubdate eq '';
        die "Duplicate link $url at $pubdate (already seen at $indexnyhet{$url}->{date})\n"
            if defined $indexnyhet{$url};
        unshift(@indexnyhet, $url);
        $indexnyhet{$url} = {
            'date' => $pubdate,
            'updated' => $upddate,
            'title' => $headline,
            'body' => $body,
        };
        $inrecord = 0;
    }

    # TODO: This is very much like what we parse in parsearticle...

    # Find start of record
    if ($line =~ /<!-- START -->/)
    {
        $inrecord = 1;
        $foundheadline = 0;
        $doneheadline = 0;
        $headline = '';
        $foundpubdate = 0;
        $pubdate = '';
        $foundupddate = 0;
        $upddate = '';
        $foundheaderend = 0;
        $body = '';
        $url = '';
        $foundpostbodyend = 0;
        next INDEXLINE;
    }
    next INDEXLINE unless $inrecord;

    # Find headline, might span several lines
    $foundheadline = 1 if $line =~ /^<b><big>/;
    $doneheadline = 1 if $line =~ /^<\/big>/;
    if ($foundheadline && !$doneheadline)
    {
        $line =~ s/^<b><big>//g;
        $line =~ s/^<!-- Overskrift-->//g;
        chomp $line;
        $headline .= $line;
    }

    # Locate publish date
    $foundpubdate = 1 if $line =~ /^Publisert/;
    next INDEXLINE unless $foundpubdate;
    if ($pubdate eq '')
    {
        if ($line =~ /([0-9][0-9])\.([0-9][0-9])\.([0-9][0-9])/)
        {
            $pubdate = "20$3-$2-$1"; # YYYY-MM-DD
        }
        next INDEXLINE;
    }
    # Locate edit date
    $foundupddate = 1 if $line =~ /^Sist endret/;
    next INDEXLINE unless $foundupddate;
    if ($upddate eq '')
    {
        if ($line =~ /([0-9][0-9])\.?([0-9][0-9])\.([0-9][0-9])/)
        {
            $upddate = "20$3-$2-$1"; # YYYY-MM-DD
        }
        next INDEXLINE;
    }

    # Locate article intro and link HTML
    if (!$foundheaderend && $line =~ /<\/center>/)
    {
        $foundheaderend = 1;
        next INDEXLINE;
    }
    next INDEXLINE unless $foundheaderend;

    # Everything until </table> is the intro text; last line is typically a link
    next INDEXLINE if $foundpostbodyend;
    $foundpostbodyend = 1, print "== body ends\n", next INDEXLINE if $line =~ /<\/table>/;

    # Find the link line
    if ($line =~ />Les om/ ||
        $line =~ />Les mer/ ||
        $line =~ />Skriv under/ ||
        $line =~ />HageLarms side/ ||
        $line =~ />Loppemarked i kolonihagen/ ||
        $line =~ />bildene fra [sS]ommerfesten/)
    {
        if ($line =~ m'<a href="http://www\.etterstad\.no/(.*)\.php')
        {
            # Internal links are just substituted with their contents
            $url = $1 . '.php';
        }
        elsif ($line =~ /<a href="([^"]+)">/)
        {
            # External links are kept as they are
            $url = $1;
            $body .= $line;
        }
    }
    else
    {
        $body .= $line;
    }
}
close $index;
print "Done reading index.php\n\n";

# Now import the archive articles. These all have their complete body in the
# linked PHP file, or is just an external link
print "Importing archived articles\n";
ARCHIVEENTRY: foreach my $nyhet (@arkivnyhet)
{
    my ($pubdate, $title, $url) = ($arkivnyhet{$nyhet}->{date}, $arkivnyhet{$nyhet}->{title}, $nyhet);
    if (defined $indexnyhet{$url}) {
        print "Dropping archived article that is also in current ($pubdate - $title)\n";
        next ARCHIVEENTRY;
    }

    print "Adding article ($pubdate - $title): ";
    if ($url !~ m@://@ && $url =~ /php$/)
    {
        # Parse PHP file
        print "parsing $url\n";
        &parsearticle($out, $url, $pubdate, $title);
    }
    else
    {
        # External article, just print what we have
        print "linking to $url\n";
        &xmlrecord($out, $pubdate, $title, $pubdate, $pubdate, '', "&lt;a href=\"$url\"&gt;$title&lt;/a&gt;");
    }
}
print "Done importing archived articles\n\n";

# Now import the current articles. Articles in linked PHP files have an external
# body that we want to put in "read more" setting
print "Importing current articles\n";
foreach my $nyhet (@indexnyhet)
{
    my ($pubdate, $title, $body, $url) = ($indexnyhet{$nyhet}->{date}, $indexnyhet{$nyhet}->{title}, $indexnyhet{$nyhet}->{body}, $nyhet);
    print "Adding article ($pubdate - $title): ";
    if ($url !~ m@://@ && $url =~ /php$/)
    {
        # Parse PHP file
        # TODO: Add $body
        print "parsing $url\n";
        &parsearticle($out, $url, $pubdate, $title);
    }
    elsif ($url =~ /^dummy/)
    {
        # No link to parse, just the body from the index page
        print "article has no external body nor link\n";
        &xmlrecord($out, $pubdate, $title, $pubdate, $pubdate, '', $body);
    }
    else
    {
        # External article, just print what we have
        print "linking to $url\n";
        &xmlrecord($out, $pubdate, $title, $pubdate, $pubdate, '', $body);
    }
}
print "Done importing current articles\n\n";

# Close the root element
print $out "</etterstad>\n";
print "Done importing articles\n";
0;

# Read a single article, and output one XML record per file
sub parsearticle
{
    my ($out, $nyhet, $origpubdate, $origheadline) = @_;

    # Ignore known bad files
    if ($nyhet eq 'nyhet1a.php' ||
        $nyhet eq 'nyhet2a.php' ||
        $nyhet eq 'nyhet279a.php' ||
        $nyhet eq 'nyhet279b.php' ||
        $nyhet eq 'nyhet279c.php' ||
        $nyhet eq 'nyhet565.php' ||
        $nyhet eq 'nyhet909.php' ||
        $nyhet eq 'nyhet1087.php' ||
        $nyhet eq 'tur0.php' ||
        $nyhet eq 'Stang.php' ||
        $nyhet eq 'bokkafe31.php' ||
        $nyhet eq 'bokkafe.php' ||
        $nyhet =~ /^index\.php/)
    {
        print "- $nyhet ($origheadline) is known to be broken, ignoring\n";
        return;
    }
    # Ignore some other files as well
    if ($nyhet eq 'nyhet150.php')
    {
        print "- ignoring $nyhet ($origheadline)\n";
        return;
    }

    # Open and read the file
    open my $file, '<:encoding(windows-1252):crlf', 'enytt/' . $nyhet
        or die "Unable to open $nyhet: $!";

    my $foundstart = 0;
    my $headline = '';
    my $foundpubdate = 0;
    my $pubdate = '';
    my $foundupddate = 0;
    my $upddate = '';
    my $foundimage = 0;
    my $image = '';
    my $foundheaderend = 0;
    my $body = '';
    my $line;

    # Read the entire file into a variable to allow us to handle multiple
    # file-endings (sometimes there are more than one in a single file)
    $/ = undef;
    my $contents = <$file>;

    # Split $contents at line terminators into the array @lines and read
    # until we are out of lines
    LINE: for (my @lines = split(/[\r\n]/,$contents); $#lines >= 0; $line = shift(@lines))
    {
        # Sometimes, Perl does weird things; ignore them
        next LINE if !defined $line;

        # Special-case nyhet10.php and nyhet015.php
        if ($line =~ /<center><b><big>(.*)<\/big><\/b><br><font size="1">Oppdatert ([0-9][0-9])\.([0-9][0-9])\.([0-9][0-9])<\/font>/)
        {
            $foundstart = 1;
            $headline = $1;
            $foundpubdate = 1;
            $pubdate = "20$3-$2-$1"; # YYYY-MM-DD
            $foundupddate = 1;
            $upddate = $pubdate;
            $foundimage = 1;
            $foundheaderend = 1;

            # Skip </center><hr><br> from nyhet015.php
            $line = shift(@lines);#<$file>;
            if ($line ne '</center><hr><br>')
            {
                $line =~ s/\r//g;
                $body = $line;
            }

            # Put everything until </TABLE> into body
            for (; $#lines >= 0; $line = shift(@lines))
            {
                last LINE if $line =~ /<\/TABLE>/;
                $body .= $line;
                $body .= "\n";
            }

            last LINE;
        }

        # Ignore everything up to "Overskrift"
        $foundstart = 1 if $line =~ /^<!-- Overskrift-->/;
        $foundstart = 1 if $line =~ /^<!-- Overskrift---->/; # nyhet566.php is broken
        $foundstart = 1, next LINE if $line =~ /^<b><big>/; # a few files are missing the comment
        next LINE unless $foundstart;

        # Ignore everything from SLUTT
        last LINE if $line =~ /^<!-- SLUTT -->/;

        # The first line after "<!--Overskrift-->" has the headline;
        # sometimes it is on the same line as the comment
        if ($headline eq '')
        {
            chomp $line;
            $line =~ s/<!-- Overskrift-->//g;
            $headline = $line;
            next LINE;
        }

        # Locate publish date
        $foundpubdate = 1 if $line =~ /^<!-- Pub\.dato -->/;
        $foundpubdate = 1 if $line =~ /^Publisert</; # nyhet1004.php is missing the comment marker
        next LINE unless $foundpubdate;
        if ($pubdate eq '')
        {
            if ($line =~ /([0-9][0-9])\.([0-9][0-9])\.([0-9][0-9])/)
            {
                $pubdate = "20$3-$2-$1"; # YYYY-MM-DD
            }
            next LINE;
        }

        # Locate edit date
        $foundupddate = 1 if $line =~ /^<!--  Oppd\. dato -->/;
        $foundupddate = 1 if $line =~ /^Sist endret/; # nyhet456.php is missing the comment marker
        next LINE unless $foundupddate;
        if ($upddate eq '')
        {
            if ($line =~ /([0-9][0-9])\.([0-9][0-9])\.([0-9][0-9])/)
            {
                $upddate = "20$3-$2-$1"; # YYYY-MM-DD
            }
            next LINE;
        }

        # Locate possible post header image
        $foundimage = 1 if $line =~ /<!--Bilde -->/;
        if (!$foundheaderend && $image eq '')
        {
            if ($line =~ /<img/)
            {
                if ($line =~ /src="([^"]+)"/)
                {
                    $image = $1;
                }
            }
            # nyhet1024.php has an image, but is missing the tag
            if ($line =~ /^<img src="(valhistmin\.gif)"/)
            {
                $foundimage = 1;
            }
        }

        # Locate text post body HTML; ignore the header end </center>
        # but possible parse an image if we find it
        if (!$foundheaderend && $line =~ /<\/center>/)
        {
            $foundheaderend = 1;
            if ($image eq '' && $body eq '' && $line =~ /<center>(<img src[^>]+>)<\/center>/)
            {
                $body = $1;
                $body .= "<br>\n";
            }
            next LINE;
        }
        next LINE unless $foundheaderend;
        next LINE if $line =~ /<!-- Tekst -->/;

        # Everything else is the text body (end-of-body marker was handled above)
        $body .= $line;
        if ($line ne '' || substr($body, -2, 2) ne "\n\n")
        {
            $body .= "\n";
        }
    }

    # Ignore some errors
    if (!$foundimage)
    {
        $foundimage = 1 if $nyhet eq 'nyhet1025.php';
    }

    # Sanity checks
    die "Did not find <!-- Overskrift--> in $nyhet" unless $foundstart;
    die "Did not find <!-- Pub.dato --> in $nyhet" unless $foundpubdate;
    die "Did not find <!--  Oppd. dato --> in $nyhet" unless $foundupddate;
    die "Did not find <!--Bilde --> in $nyhet" unless $foundimage;
    die "Did not find </center> (end of header) in $nyhet" unless $foundheaderend;
    die "Could not parse headline in $nyhet" if $headline eq '';
    die "Could not parse publish date in $nyhet" if $pubdate eq '';
    die "Could not parse update date in $nyhet" if $upddate eq '';
    die "Could not parse text body in $nyhet" unless $body =~ /\w/;

    # Always use the publication date listed in the index
    if ($pubdate ne $origpubdate)
    {
        print "- $nyhet publication date $pubdate does not match index $origpubdate\n";
        $pubdate = $origpubdate;
    }

    # Drop trailing table close tag
    $body =~ s@</td></tr></table></td></tr></table><br>\n$@@ms;
    # Drop trailing <br>
    my $done = 0;
    while (!$done)
    {
        $done = 1;
        $done = 0, substr($body, 0, 4) = ''  if substr($body, 0, 4) eq '<br>';
        $done = 0, substr($body, 0, 1) = ''  if substr($body, 0, 1) eq "\n";
        $done = 0, substr($body, -1, 1) = '' if substr($body, -1) eq "\n";
        $done = 0, substr($body, -4, 4) = '' if substr($body, -4) eq "<br>";
    };

    # If in-file headline is different from the index headline, we add it
    if ($headline ne $origheadline)
    {
        $body = "<h1>$origheadline</h1>\n" . $body;
    }

    # Escape body HTML to make it valid inside the XML file
    $body =~ s/&/&amp;/g;
    $body =~ s/</&lt;/g;
    $body =~ s/>/&gt;/g;

    # Output an XML record for this post
    &xmlrecord($out, $nyhet, $headline, $pubdate, $upddate, $image, $body);
}

sub xmlrecord
{
    my ($out, $id, $headline, $pubdate, $upddate, $image, $body) = @_;

    print $out "<article>\n";
    print $out "  <id>$id</id>\n";
    print $out "  <headline>$headline</headline>\n";
    print $out "  <published>$pubdate</published>\n";
    print $out "  <edited>$upddate</edited>\n";
    print $out "  <image>$image</image>\n" if $image ne '';
    print $out "  <body>$body</body>\n";
    print $out "</article>\n";
}

