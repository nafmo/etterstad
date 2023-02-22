#!/usr/bin/perl -w

use utf8;

# We want to output UTF-8
binmode(STDOUT, ':utf8');

# Write export opening
open my $out, '>:encoding(utf-8)', 'referatene.xml'
    or die "Unable to write referatene.xml: $!";
my $now = scalar localtime;
print $out <<"EOM";
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/"
 xmlns:content="http://purl.org/rss/1.0/modules/content/"
 xmlns:wfw="http://wellformedweb.org/CommentAPI/"
 xmlns:dc="http://purl.org/dc/elements/1.1/"
 xmlns:wp="http://wordpress.org/export/1.2/">
<channel>
 <title>Etterstad Vel</title>
 <link>http://etterstad.no/</link>
 <description>Etterstad.no</description>
 <pubDate>$now</pubDate>
 <language>nb</language>
 <wp:wxr_version>1.2</wp:wxr_version>
 <wp:base_site_url>http://etterstad.no/</wp:base_site_url>
 <wp:base_blog_url>http://etterstad.no/</wp:base_blog_url>
 <wp:author>
  <wp:author_id>1</wp:author_id>
  <wp:author_login>etterstad</wp:author_login>
  <wp:author_email>post\@etterstad.no</wp:author_email>
  <wp:author_display_name>Etterstad.no</wp:author_display_name>
  <wp:author_first_name>Etterstad.no</wp:author_first_name>
  <wp:author_last_name></wp:author_last_name>
 </wp:author>
EOM

# Write categories
my %categories = (
    'referat' => 7,
);
my $catnum = 0;
foreach my $category (sort(keys %categories))
{
    print $out <<"EOM";
 <wp:category>
  <wp:term_id>$categories{$category}</wp:term_id>
  <wp:category_nicename>$category</wp:category_nicename>
  <wp:category_parent></wp:category_parent>
  <wp:cat_name>$category</wp:cat_name>
 </wp:category>
EOM
}

# Count posts
my $postnum = 0;

# Read through the index of the meeting notes.
# They are sorted in reverse chronological order, so read
# them all first and then process
open my $referat, '<:encoding(windows-1252):crlf', 'enytt/referatene/referat.html'
    or die "Unable to open arkivet.php: $!";

my @referat;
my %referat;

print "Reading referat.html\n";
$/ = "\n";
my $referatlist = 0;
REFERATLINE: while (my $line = <$referat>)
{
    # Find start of index
    $referatlist = 1 if $line =~ /^<a href="alleref/;
    next REFERATLINE if !$referatlist;
    last REFERATLINE if $line =~ /<!-- SLUTT INNHOLD -->/;
    
    # Find lines with meeting note links, internal or external
    if ($line =~ /^<a href="([0-9].*\.html?)">(.*)<\/a><br>/)
    {
        # Extract metadata
        my ($url, $title) = ($1, $2);
        my ($y, $m, $d);
        if ($url =~ /^([12][09][0-9][0-9])_([0-1][0-9])_([0-3][0-9])[a-z]?\./)
        {
            $y = $1;
            $m = $2;
            $d = $3;
        }
        elsif ($url =~ /^([0-3][0-9])([0-1][0-9])([7890][0-9])[a-z]?\./)
        {
            if ($3 > 25)
            {
                $y = "19$3";
            }
            else
            {
                $y = "20$3";
            }
            $m = $2;
            $d = $1;
        }
        # Handle unknown days (00)
        if ($d == "00")
        {
            $d = "01";
            # Two unknown days in May 1994
            if ($url eq '000594.htm')
            {
                $d = "20";
                $title .= ' (2)';
            }
            print " $url has day number zero, adjusting to $d\n";
        }
        my $pubdate = "$y-$m-$d";

        # Drop broken article link
        next REFERATLINE if $pubdate eq '2001-01-15';

        # Fix broken title
        $title = 'Protokoll fra årsmøte 30. oktober 2001' if $url eq '301001a.htm';

        print "Found article $url: $pubdate - $title\n";

        # Some of the stories are linked twice, keep the newest (first) copy
        if (defined $referat{$url})
        {
            print "Duplicate link $url at $pubdate (already seen at $referat{$url}->{date})\n";
            next REFERATLINE;
        }

        unshift(@referat, $url);
        $referat{$url} = {
            'date' => $pubdate,
            'title' => $title,
            'num' => ++ $postnum,
        };
    }
    else
    {
        print "Skipping $line";
    }
}
print "Done reading referat.html\n\n";
close $referat;

# Keep user-friendly URLs for all pages
my %redirect;
my %directre; # the opposite of above, to detect duplicates
my %postname; # the dateless name must be unique, too

# Now import the meeting notes. Articles in linked HTML files have an external
# body that we want import.
print "Importing meeting notes\n";
foreach my $referat (@referat)
{
    my ($pubdate, $title, $url, $num) = ($referat{$referat}->{date}, $referat{$referat}->{title}, $referat, $referat{$referat}->{num});

    print "Adding meeting notes ($pubdate - $title):\n";
    # Parse HTML files
    $xml .= &parsearticle($out, $num, $url, $pubdate, $title);
}
print "Done importing meeting notes articles\n\n";

# Rewrite URLs
# $xml =~ s/<a href="(nyhet[^">]+php)"/sprintf('<a href="%s"',&findredirect($1));/ge;
# $xml =~ s/<a href="http:\/\/www\.etterstad\.no\/(nyhet[^">]+php)"/sprintf('<a href="%s"',&findredirect($1));/ge;
print $out $xml;

# Close the RSS feed
print $out "</channel></rss>\n";
print "Done importing articles\n\n";

# Write htaccess rewrite rules
print "Exporting article redirect map\n";
open my $htaccess, '>:encoding(utf-8)', 'htaccess-referatene.txt'
    or die "Unable to write htaccess-referatene.txt: $!";
foreach my $old (sort(keys %redirect))
{
    print $htaccess qq'Redirect permanent "/$old" "$redirect{$old}"\n';
}
close $htaccess;
print "Done exporting article redirect map\n";
0;

# Read a single article, and output one XML record per file
sub parsearticle
{
    my ($out, $num, $nyhet, $origpubdate, $origheadline) = @_;

    # Ignore known bad files
#    if ($nyhet eq 'nyhet1a.php' ||
#        $nyhet =~ /^index\.php/)
#    {
#        print "- $nyhet ($origheadline) is known to be broken, ignoring\n";
#        return '';
#    }
#    # Ignore some other files as well
#    if ($nyhet eq 'nyhet150.php')
#    {
#        print "- ignoring $nyhet ($origheadline)\n";
#        return '';
#    }

    # Open and read the file
    open my $file, '<:encoding(windows-1252):crlf', 'enytt/referatene/' . $nyhet
        or die "Unable to open $nyhet: $!";

    my $foundstart = 0;
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

        # Ignore everything up to "INNHOLD START"
        $foundstart = 1 if $line =~ /^<!-- INNHOLD START -->/;
#        if (!$foundstart)
#        {
#            # Some files are broken, find the headline anyway
#            if ($line =~ /^<b><big>([^<>]+)$/)
#            {
#                $headline = $1;
#                $foundstart = 1;
#                next LINE;
#            }
#        }
        $foundstart = 1, next LINE if $line =~ /REFERAT FRA STYREMØTE/; # a few files are missing the comment
        next LINE unless $foundstart;

        # Ignore everything from SLUTT
        last LINE if $line =~ /<!-- INNHOLD SLUTT -->/;

        # Ignore everything until the line that closes the header table, we use the title from
        # the index page, ignoring the one in the page itself

        if (!$foundheaderend && $line =~ /<\/table>/)
        {
            $foundheaderend = 1;
            next LINE;
        }
        next LINE unless $foundheaderend;

        # Everything else is the text body (end-of-body marker was handled above)
        $body .= $line;
        if ($line ne '' || substr($body, -2, 2) ne "\n\n")
        {
            $body .= "\n";
        }
    }

    # Sanity checks
    die "Did not find <!-- INNHOLD START --> in $nyhet" unless $foundstart;
    die "Did not find </table> (end of header) in $nyhet" unless $foundheaderend;
    die "Could not parse text body in $nyhet" unless $body =~ /\w/;

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
        $done = 0, substr($body, -18, 18) = '' if substr($body, -18) eq '</td></tr></table>';
    };

    # Rewrite image URLs to point to top
    $body =~ s@<img src="(?!http)@<img src="/referatene/@g;
    $body =~ s@<img src="/referatene//@<img src="/@g;

    # Output an XML record for this post
    return &xmlrecord($out, $num, $nyhet, $origheadline, $origpubdate, $body);
}

sub xmlrecord
{
    my ($out, $num, $id, $headline, $pubdate, $body) = @_;

    # Make a permalink http://etterstad.no/YYYY/MM/DD/title
    my $ymdurl = $pubdate;
    $ymdurl =~ s/-/\//g;
    my $headlineurl = lc($headline);
    $headlineurl =~ tr/æøå /aoa-/;
    $headlineurl =~ s/[^-a-z0-9_]//g;
    my $linkname = "http://etterstad.no/$ymdurl/$headlineurl";
    if (defined $redirect{$id})
    {
        die "We have seen $id before, it is already redirected to $redirect{$id}\n";
    }

    # Select a (rough) category for the post
    my $category = 'referat';
    # Create unique permalink
    my $origlinkname = $linkname;
    my $linkcounter = 1;
    while (defined $directre{$linkname} || defined $postname{"$headlineurl-$linkcounter"})
    {
        die "Duplicate permalink $linkname\n";
        $linkname = $origlinkname . "-" . (++ $linkcounter);
    }
    $redirect{$id} = $linkname;
    $directre{$linkname} = $id;
    $postname{"$headlineurl-$linkcounter"} = 1;
    # Import regenerates the permalink from the headline, so update the headline too
    $headline .= " ($linkcounter)" if $linkcounter > 1;
    $headlineurl .= "-$linkcounter" if $linkcounter > 1;

    # Output the post in WordPress extended RSS format
    return <<"EOM";
 <item>
  <title><![CDATA[$headline]]></title>
  <link>$linkname</link>
  <pubDate>$pubdate</pubDate>
  <dc:creator>etterstad</dc:creator>
  <guid isPermaLink="false">http://etterstad.no/referatene/$id</guid>
  <description></description>
  <excerpt:encoded></excerpt:encoded>
  <content:encoded><![CDATA[$body]]></content:encoded>
  <wp:post_id>$num</wp:post_id>
  <wp:post_date>$pubdate</wp:post_date>
  <wp:post_date_gmt>$pubdate</wp:post_date_gmt>
  <wp:post_modified>$pubdate</wp:post_modified>
  <wp:post_modified_gmt>$pubdate</wp:post_modified_gmt>
  <wp:comment_status>closed</wp:comment_status>
  <wp:ping_status>closed</wp:ping_status>
  <wp:post_name>$headlineurl</wp:post_name>
  <wp:status>publish</wp:status>
  <wp:post_parent>0</wp:post_parent>
  <wp:menu_order>0</wp:menu_order>
  <wp:post_type>post</wp:post_type>
  <wp:post_password></wp:post_password>
  <wp:is_sticky>0</wp:is_sticky>
  <category domain="category" nicename="$category">$category</category>
 </item>
EOM
}

sub findredirect
{
    my $origurl = shift;
    return $redirect{$origurl} if defined $redirect{$origurl};
    $origurl =~ s/,php/.php/;
    $origurl =~ s/691c/691/;
    $origurl =~ s/i\.php/.php/;
    return $redirect{$origurl} if defined $redirect{$origurl};
    die "$origurl is not in link database\n";
    return $origurl;
}
