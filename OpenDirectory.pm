# OpenDirectory.pm
# by Jim Smyser
# Copyright (c) 1999 by Jim Smyser & USC/ISI
# $Id: OpenDirectory.pm,v 2.02 2000/01/30 04:00:55 jims Exp $


package WWW::Search::OpenDirectory;

=head1 NAME

WWW::Search::OpenDirectory - class for searching dmoz.org! 


=head1 SYNOPSIS

    require WWW::Search;
    $search = new WWW::Search('OpenDirectory');

=head1 DESCRIPTION

This class uses the Open Directory engine F<http://dmoz.org>.
Yahoo! type directory that is user maintained. Very nice!

Seperate search terms with 'and' to include all words. Accepts
double quotes for phrase searching: "Tour de France"

This class exports no public interface; all interaction should
be done through WWW::Search objects.

=head1 SEE ALSO

To make new back-ends, see L<WWW::Search>,
or the specialized AltaVista searches described in options.

=head1 HOW DOES IT WORK?

C<native_setup_search> is called before we do anything.
It initializes our private variables (which all begin with underscores)
and sets up a URL to the first results page in C<{_next_url}>.

C<native_retrieve_some> is called (from C<WWW::Search::retrieve_some>)
whenever more hits are needed.  It calls the LWP library
to fetch the page specified by C<{_next_url}>.
It parses this page, appending any search hits it finds to 
C<{cache}>.  If it finds a ``next'' button in the text,
it sets C<{_next_url}> to point to the page for the next
set of results, otherwise it sets it to undef to indicate we're done.

=head1 AUTHOR

C<WWW::Search::OpenDirectory> is written and maintained
by Jim Smyser - <jsmyser@bigfoot.com>.

=head1 TESTING

This module adheres to the C<WWW::Search> test suite mechanism. 
See $TEST_CASES below.

=head1 LEGALESE

Copyright (c) 1996-1999 University of Southern California.
All rights reserved.                                            
                                                               
THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

=head1 VERSION HISTORY

2.01
New test mechanism.

1.02
Format changes.

=cut
#'

#####################################################################

require Exporter;
@EXPORT = qw();
@EXPORT_OK = qw();
$VERSION = '2.02';
@ISA = qw(WWW::Search Exporter);

$MAINTAINER = 'Jim Smyser <jsmyser@bigfoot.com>';
$TEST_CASES = <<"ENDTESTCASES";
&test('OpenDirectory', '$MAINTAINER', 'zero', \$bogus_query, \$TEST_EXACTLY);
&test('OpenDirectory', '$MAINTAINER', 'one', 'iRover', \$TEST_RANGE, 2,10);
&test('OpenDirectory', '$MAINTAINER', 'multi', 'Hasbro', \$TEST_GREATER_THAN, 26);
ENDTESTCASES

use Carp ();
use WWW::Search(generic_option);
require WWW::SearchResult;

# private
sub native_setup_search
{
   my($self, $native_query, $native_options_ref) = @_;
   $self->user_agent('user');
   $self->{_next_to_retrieve} = 0;
   if (!defined($self->{_options})) {
   $self->{_options} = {
       'search_url' => 'http://search.dmoz.org/cgi-bin/search',

    };
    };
   my($options_ref) = $self->{_options};
   if (defined($native_options_ref)) {
   # Copy in new options.
   foreach (keys %$native_options_ref) {
       $options_ref->{$_} = $native_options_ref->{$_};
   };
   };
   # Process the options.
   my($options) = '';
   foreach (keys %$options_ref) {
   # printf STDERR "option: $_ is " . $options_ref->{$_} . "\n";
   next if (generic_option($_));
   $options .= $_ . '=' . $options_ref->{$_} . '&';
   };
   $self->{_debug} = $options_ref->{'search_debug'};
   $self->{_debug} = 2 if ($options_ref->{'search_parse_debug'});
   $self->{_debug} = 0 if (!defined($self->{_debug}));
   # Finally figure out the url.
   $self->{_base_url} = 
   $self->{_next_url} =
   $self->{_options}{'search_url'} .
   "?" . $options .
   "search=" . $native_query;
}

# private
sub native_retrieve_some {

   my ($self) = @_;
   # fast exit if already done
   return undef if (!defined($self->{_next_url}));

   # get some
   print STDERR "**Fetching some....\n" if 2 <= $self->{_debug};
   my($response) = $self->http_request('GET', $self->{_next_url});
   $self->{response} = $response;
   if (!$response->is_success) {
   return undef;
   };
   # parse the output
   my($HEADER, $HITS, $DESC, $TRAILER, $POST_NEXT) = (1..10);
   my($hits_found) = 0;
   my($state) = ($HEADER);
   my($hit, $raw, $title, $url, $desc) = ();
   foreach ($self->split_lines($response->content())) {
       next if m@^$@; # short circuit for blank lines
   if ($state == $HEADER && m|<b>Open Directory Sites</b>|i) { 
       print STDERR "PARSE(HEADER->HITS-1): $_\n" if ($self->{_debug} >= 2);
       $state = $HITS;

  } elsif ($state == $HITS && m@<lI><a href="([^"]+)">(.*)</a>.*?-(.*)<br><small>@i) { 
       print STDERR "**Parsing URL, Title & Desc...\n" if 2 <= $self->{_debug};
       my($hit) = new WWW::SearchResult;
       $hit->add_url($1);
       $hit->title($2);
       $hit->description($3);
       $hit->raw($_);
       $hits_found++;
       push(@{$self->{cache}}, $hit);
       $state = $HITS;
  } elsif ($state == $HITS && m@</ol><p>@i) {
       print STDERR "PARSE(HITS->TRAILER): $_\n\n" if ($self->{_debug} >= 2);
       $state = $TRAILER;
  } elsif ($state == $TRAILER && m@<a href="([^"]+)">Next</a>@i) { 
       my($sURL) = $1;
       $self->{_next_url} = new URI::URL($sURL, $self->{_base_url});
       print STDERR "PARSE(TRAILER->POST_NEXT): $_\n\n" if ($self->{_debug} >= 2);
       $state = $POST_NEXT;
       } else {
       print STDERR "PARSE: read:\"$_\"\n" if ($self->{_debug} >= 2);
    };
    };
    if ($state != $POST_NEXT) {
    # no more 'next' tags
    if (defined($hit)) {
        push(@{$self->{cache}}, $hit);
    };
    $self->{_next_url} = undef;
    };
    # sleep so as to not overload server
    $self->user_agent_delay if (defined($self->{_next_url}));

    return $hits_found;
}

1;
