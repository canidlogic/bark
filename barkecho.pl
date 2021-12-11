#!/usr/bin/env perl
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Non-core modules
use MIME::Parser;

# Core modules
use Encode qw(decode);
use File::Temp qw(tempdir);

=head1 NAME

barkecho.pl - Given a Bark-format MIME message, compile it into UTF-8
text output.

=head1 SYNOPSIS

  barkecho.pl < input.msg > output.txt

=head1 DESCRIPTION

A Bark-format MIME message is read from standard input.  (See the
documentation in the C<barkmime.pl> script for specifics of this MIME
message format.)

Each separate section of the MIME message is combined into a single text
stream without the MIME container and then written to standard output.

=cut

# ===================
# Temporary directory
# ===================

# Create a temporary directory that will be used by the MIME parser for
# parsing messages, and indicate that the temporary directory and all
# files contained within should be deleted when the script ends
#
my $mime_dir = tempdir(CLEANUP => 1);

# ==================
# Program entrypoint
# ==================

# First off, set standard output to use UTF-8
#
binmode(STDOUT, ":encoding(utf8)") or
  die "Failed to change standard output to UTF-8, stopped";

# Check that no parameters
#
($#ARGV == -1) or die "Not expecting program arguments, stopped";

# Parse the MIME message from standard input
#
my $parser = MIME::Parser->new;
$parser->output_dir($mime_dir);

my $ent = $parser->parse(\*STDIN);

# Make sure MIME message is type multipart/mixed
#
($ent->mime_type eq 'multipart/mixed') or
  die "MIME message in wrong format, stopped";

# Process each part of the message
#
my $last_footer;
for(my $i = 0; $i < $ent->parts; $i++) {
  
  # Get the current part
  my $p = $ent->parts($i);
  
  # Make sure part is a plain-text format
  (($p->mime_type =~ /^text\/plain$/ui) or
      ($p->mime_type =~ /^text\/plain;/ui)) or
    die "Wrong MIME part type, stopped";
  
  # Open the current part for reading, in binary mode so we can manually
  # decode to UTF-8
  $p = $p->bodyhandle;
  $p->binmode(1);
  my $io = $p->open("r");
  
  # Read the initial footer line from the part and trim trailing LF or
  # CR+LF
  my $footer;
  ($footer = $io->getline) or
    die "Failed to read MIME initial footer, stopped";
  $footer = decode("UTF-8", $footer);
  $footer =~ s/[\r\n]*$//ug;
  
  # If this is not the first part, make sure footer is same as in last
  # part; else, store the first part's footer in last_footer
  if ($i > 0) {
    ($last_footer eq $footer) or
      die "Footer changes between parts, stopped";
  } else {
    $last_footer = $footer;
  }
  
  # Read the header line from the part
  my $first_line;
  ($first_line = $io->getline) or
    die "Failed to read MIME part header line, stopped";
  $first_line = decode("UTF-8", $first_line);
  
  # Decode the header line
  ($first_line =~ /^(\+|:)([A-Za-z0-9_\-]+)[ \t\r\n]*$/u) or
    die "MIME part header line in invalid format, stopped";
  my $join_mode = $1;
  my $style_name = $2;
  
  # Check style name
  (($style_name eq '-') or (not ($style_name =~ /\-/u))) or
    die "MIME part header has invalid style, stopped";
  
  # If this is not the first part AND the join style is ":" then insert
  # a line break to separate from previous section
  if (($i > 0) and ($join_mode eq ':')) {
    print "\n";
  }
  
  # Read and echo all lines until we hit the footer line
  my $first_line = 1;
  my $found_footer = 0;
  while (my $dl = $io->getline) {
    
    # Decode the current line to UTF-8
    $dl = decode("UTF-8", $dl);
    
    # Strip line break
    $dl =~ s/[\r\n]*$//ug;
    
    # If this is the footer line, we are done with the loop
    if ($dl eq $footer) {
      $found_footer = 1;
      last;
    }
    
    # If this is the first line, clear the first line flag; else, insert
    # a line break after the previous line
    if ($first_line) {
      $first_line = 0;
    } else {
      print "\n";
    }
    
    # Now print the line without any linebreak after it
    print $dl;
  }
  if (not $found_footer) {
    die "MIME part missing footer, stopped";
  }
  
  # We've hit the footer line, so read the rest of the data in the MIME
  # part, making sure each line is blank or empty
  while (my $bl = $io->getline) {
    $bl = decode("UTF-8", $bl);
    ($bl =~ /^[ \t\r\n]*$/u) or
      die "MIME part contains data after footer, stopped";
  }
  
  # Close the MIME part reader handle
  close($io);
}

# Final line break at the end
#
print "\n";

# Purge disk files of the MIME parser
#
$ent->purge;

=head1 AUTHOR

Noah Johnson, C<noah.johnson@loupmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2021 Multimedia Data Technology Inc.

MIT License:

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files
(the "Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=cut
