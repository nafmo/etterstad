#!/usr/bin/perl -w

# We want to output UTF-8
binmode(STDOUT, ':utf8');

# Find all nyhet<num>.php
opendir(my $enytt, 'enytt') or die "Unable to open enytt: $!\n";
my @nyhet = sort { 
    my $first = $a;
    $first =~ s/[^0-9]//g;
    my $second = $b;
    $second =~ s/[^0-9]//g;
    $first == $second ? $a cmp $b : $first <=> $second;
} grep { /^nyhet[0-9].*php/ && -f "enytt/$_" } readdir($enytt);
closedir $enytt;

open my $out, '>:encoding(utf-8)', 'enytt.xml'
    or die "Unable to write enytt.xml: $!";

# Write pre-amble and root element
print $out qq'<?xml version="1.0" encoding="utf-8"?>\n';
print $out "<etterstad>\n";

# Now read each article, and output one XML record per file
ARTICLE: foreach my $nyhet (@nyhet)
{
    # Ignore known bad files
    next ARTICLE if $nyhet eq 'nyhet1a.php';
    next ARTICLE if $nyhet eq 'nyhet2a.php';
    next ARTICLE if $nyhet eq 'nyhet279a.php';
    next ARTICLE if $nyhet eq 'nyhet279b.php';
    next ARTICLE if $nyhet eq 'nyhet279c.php';
    next ARTICLE if $nyhet eq 'nyhet565.php';
    next ARTICLE if $nyhet eq 'nyhet909.php';
    next ARTICLE if $nyhet eq 'nyhet1087.php';

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
        $foundheaderend = 1, next LINE if $line =~ /<\/center>/;
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

    # Drop trailing table close tag
    $body =~ s@</td></tr></table></td></tr></table><br>\n$@@ms;
    # Drop trailing <br>
    my $done = 0;
    while (!$done)
    {
        $done = 1;
        $done = 0, substr($body, -4, 4) = '' if substr($body, -4) eq "<br>";
        $done = 0, substr($body, -1, 1) = '' if substr($body, -1) eq "\n";
    };


    # Escape body HTML to make it valid inside the XML file
    $body =~ s/&/&amp;/g;
    $body =~ s/</&lt;/g;
    $body =~ s/>/&gt;/g;

    # Output an XML record for this post
    print $out "<article>\n";
    print $out "  <id>$nyhet</id>\n";
    print $out "  <headline>$headline</headline>\n";
    print $out "  <published>$pubdate</published>\n";
    print $out "  <edited>$upddate</edited>\n";
    print $out "  <image>$image</image>\n" if $image ne '';
    print $out "  <body>$body</body>\n";
    print $out "</article>\n";
}

# Close the root element
print $out "</etterstad>\n";
