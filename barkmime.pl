#!/usr/bin/env perl
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Non-core modules
use MIME::Entity;

# Core modules
use File::Temp qw(tempfile);

=head1 NAME

barkmime.pl - Given a Bark Text File (BTF), pack it into a Bark-format
MIME message.

=head1 SYNOPSIS

  barkmime.pl < input.btf > out.msg

=head1 DESCRIPTION

The Bark Text File is read from standard input.  It is packed into a
MIME message with multipart/mixed format.  Each part is text/plain in
UTF-8 encoding.  The body of each part begins with a footer line (so the
actual footer can be detected), then a header line, then zero or more
content lines, and then the footer line again, followed by zero or more
blank or empty lines.

The header line of each part begins with a colon or plus symbol.  Colon
is used if there should be a line break after the last line of the
previous section, plus if not.  (No difference in meaning for the very
first section.)  After that, without whitespace in-between, there is a
sequence of one or more alphanumeric and underscore characters defining
a style name for the section, or a single hyphen indicating that the
section has default style.  This is followed by optional whitespace and
then the line break.

The footer line of each part is the same for all parts.  It begins with
a less-than sign (left angle bracket) and ends with a greater-than sign
(right angle bracket).  Within the brackets is a question mark, the word
"bark", an underscore, a sequence of eleven random ASCII alphanumeric
characters, and another question mark.  The random sequence is the same
across all footers in the message.

Each part is by default encoded with quoted-printable.  You can change
this to base-64 by adding the c<-base64> option to the command line.

=cut

# ==========
# Part files
# ==========

# Each part that will be included in the MIME message has its own
# temporary file here.  There is an END block that unlinks all the
# temporary files when the script ends.
#
# The @ppaths array stores the paths to each temporary file part, in the
# order they appear in the message.
#
# The $ph handle is open for output to the last part in the array,
# unless @ppaths is empty or at the end of the script when attaching all
# the files to the MIME message and outputting it.
#
my @ppaths;
my $ph;
END {
  unlink(@ppaths);
}

# ==========
# Local data
# ==========

# The MIME entity for the message we are building.
#
my $ent = MIME::Entity->build(Type    => "multipart/mixed",
                              From    => 'author@example.com',
                              To      => 'publisher@example.com',
                              Subject => "bark");

# ===============
# Local functions
# ===============

# Generate a footer with a randomly chosen section within it.
#
# Returns:
#
#   string - the random footer, including the <? ?> and the line break
#
sub gen_footer {
  # Check parameter count
  ($#_ == -1) or die "Wrong number of parameters, stopped";
  
  # Generate 11 random alphanumeric characters
  my $rstr = '';
  while (length $rstr < 11) {
    my $d = int(rand(62));
    if ($d < 26) {
      $d = chr($d + ord('A'));
      
    } elsif ($d < 52) {
      $d = $d - 26;
      $d = chr($d + ord('a'));
      
    } else {
      $d = $d - 52;
      $d = chr($d + ord('0'));
    }
    $rstr = $rstr . $d;
  }
  
  # Return the full footer
  return "<?bark_$rstr?>\n";
}

# ==================
# Program entrypoint
# ==================

# First off, set standard input to use UTF-8
#
binmode(STDIN, ":encoding(utf8)") or
  die "Failed to change standard input to UTF-8, stopped";

# Define variables to receive option values
#
my $enc_mode = 'quoted-printable';

# Interpret program arguments
#
for(my $i = 0; $i <= $#ARGV; $i++) {
  if ($ARGV[$i] eq '-base64') {
    $enc_mode = 'base64';
    
  } else {
    die "Unrecognized option '$ARGV[$i]', stopped";
  }
}

# Read the first line from input, which must be a signature line (with
# optional UTF-8 BOM)
#
(my $first_line = <STDIN>) or die "Failed to read signature, stopped";
($first_line =~ /^(?:\x{feff})?`%bark[ \t\r\n]*$/u) or
  die "Bark signature line missing, stopped";

# Define footer line
#
my $footer = gen_footer;

# Read and interpret the rest of the lines
#
while (<STDIN>) {

  # Check whether this is an escape line and set flag
  my $is_escape = 0;
  if (/^``/u) {
    $is_escape = 1;
  }

  # Handle line type
  if ((/^`$/u) or (/^`[ \t\r\n]+/u)) { # -------------------------------
    # Comment line; skip
    next;
  
  } elsif (/^`:/u) { # -------------------------------------------------
    # Section command; if the part array is not empty, write a footer
    # line to the current part and close it
    if ($#ppaths >= 0) {
      print {$ph} $footer;
      close($ph);
    }
    
    # Determine style for this section
    my $new_style;
    if (/^`:[ \t]*([A-Za-z0-9_]+)[ \t\r\n]*$/u) {
      $new_style = $1;
      
    } elsif (/^`:[ \t\r\n]*$/u) {
      $new_style = '-';
      
    } else {
      die "Invalid section command '$_', stopped";
    }
    
    # Open a new part file and write the footer and header line
    my $tpath;
    my $th;
    ($th, $tpath) = tempfile();
    binmode($th, ":encoding(utf8)") or
      die "Failed to change temporary file to UTF-8, stopped";
    
    push @ppaths, ($tpath);
    $ph = $th;
    
    print {$ph} "$footer:$new_style\n";
    
  } elsif (/^`\+/u) { # ------------------------------------------------
    # Join command; if the part array is not empty, write a footer line
    # to the current part and close it
    if ($#ppaths >= 0) {
      print {$ph} $footer;
      close($ph);
    }
    
    # Determine style for this section
    my $new_style;
    if (/^`\+[ \t]*([A-Za-z0-9_]+)[ \t\r\n]*$/u) {
      $new_style = $1;
      
    } elsif (/^`\+[ \t\r\n]*$/u) {
      $new_style = '-';
      
    } else {
      die "Invalid join command '$_', stopped";
    }
    
    # Open a new part file and write the footer and header line
    my $tpath;
    my $th;
    ($th, $tpath) = tempfile();
    binmode($th, ":encoding(utf8)") or
      die "Failed to change temporary file to UTF-8, stopped";
    
    push @ppaths, ($tpath);
    $ph = $th;
    
    print {$ph} "$footer+$new_style\n";
  
  } elsif ((length($_) < 1) or (/^[^`]/u) or $is_escape) { # -----------
    # Data or escape line -- trim trailing line break if present
    if (/\r\n$/u) {
      # Strip CR+LF
      $_ = substr($_, 0, -2);
      
    } elsif (/\n$/u) {
      # Strip LF
      $_ = substr($_, 0, -1);
    }
    
    # If this is an escape line, drop first character
    if ($is_escape) {
      $_ = substr($_, 1);
    }
    
    # Make sure the line with a line break at the end is not exactly the
    # same as the footer line
    ("$_\n" ne $footer) or
      die "Footer collision, stopped";
    
    # If no part files have been opened yet, open a part file and write
    # a footer and header line with default style
    if ($#ppaths == -1) {
      my $tpath;
      my $th;
      ($th, $tpath) = tempfile();
      binmode($th, ":encoding(utf8)") or
        die "Failed to change temporary file to UTF-8, stopped";
      
      push @ppaths, ($tpath);
      $ph = $th;
      
      print {$ph} "$footer:-\n";
    }
    
    # Write the line to the currently opened part file
    print {$ph} "$_\n";

  } else {
    # Invalid line
    die "Invalid text line '$_', stopped";
  }
}

# Should be at least one part defined
#
($#ppaths >= 0) or die "No data lines in Bark text file, stopped";

# Write a footer line to the currently opened part file and close it
#
print {$ph} $footer;
close($ph);

# Attach all text parts to the message
#
for my $p (@ppaths) {
  $ent->attach( Path     => $p,
                Type     => "text/plain;charset=UTF-8",
                Encoding => $enc_mode);
}

# Write the whole message to standard output
#
$ent->print(\*STDOUT);

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
