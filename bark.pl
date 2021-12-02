#!/usr/bin/env perl
use strict;
use feature 'unicode_strings';
use warnings FATAL => "utf8";

# Non-core modules
use JSON::Tiny qw(decode_json);

# Core modules
use File::Temp qw/ tmpnam /;

=head1 NAME

bark.pl - Interpret a Bark text file according to a Bark dispatch file
and render the results.

=head1 SYNOPSIS

  bark.pl -style style.json < input.btf > output.txt

=head1 DESCRIPTION

The given dispatch JSON file is loaded.  The Bark text file is read and
interpreted, using the dispatch definitions to generate text rendering
pipelines.  The results are written to output.  See the README.md file
for further information.

=cut

# ==========
# Local data
# ==========

# The line buffer that stores the last line written with write_line.
#
# $linebuf_full is non-zero if there is a line buffered, zero otherwise.
#
# $linebuf_line stores the buffered line *without any line break* if
# the $linebuf_full flag is set.
#
my $linebuf_full = 0;
my $linebuf_line;

# ===============
# Local functions
# ===============

# Write a line to output, using the buffer.
#
# If the line buffer is currently full, it is written to output to clear
# it.
#
# The given line is stored in the output buffer.  It must *not* have any
# LF or CR characters in it.
#
# Use write_flush() at the end of the script to make sure the line
# buffer is flushed.
#
# Parameters:
#
#   1 : string - the line to write, without the line break
#
sub write_line {
  # Should have exactly one argument
  ($#_ == 0) or die "Wrong number of arguments, stopped";

  # Get argument and set type
  my $str = shift;
  $str = "$str";
  
  # Make sure no line break characters
  (not ($str =~ /\r|\n/u)) or
    die "Stray line break characters, stopped";
  
  # If line buffer is full, flush it with a line break afterwards
  if ($linebuf_full) {
    print "$linebuf_line\n";
    $linebuf_full = 0;
  }
  
  # Store given line in line buffer
  $linebuf_full = 1;
  $linebuf_line = $str;
}

# Flush the line buffer if any output is buffered there.
#
sub write_flush {
  # Should have no arguments
  ($#_ == -1) or die "Wrong number of arguments, stopped";

  # Flush buffer with line break
  if ($linebuf_full) {
    print "$linebuf_line\n";
    $linebuf_full = 0;
  }
}

# If line buffer is full, flush output with a line break at the end.
#
sub section_connect {
  # Should have no arguments
  ($#_ == -1) or die "Wrong number of arguments, stopped";

  # Flush buffer with line break
  if ($linebuf_full) {
    print "$linebuf_line\n";
    $linebuf_full = 0;
  }
}

# If line buffer is full, flush output WITHOUT a line break at the end.
#
sub join_connect {
  # Should have no arguments
  ($#_ == -1) or die "Wrong number of arguments, stopped";

  # Flush buffer without line break
  if ($linebuf_full) {
    print "$linebuf_line";
    $linebuf_full = 0;
  }
}

# Run buffered data at a given file path through a given pipeline, and
# write each line of the result to the write_line function.
#
# Parameters:
#
#   1 : string - the file path
#
#   2 : string - the pipeline as a shell command
#
sub flush_pipeline {
  # Should have exactly two arguments
  ($#_ == 1) or die "Wrong number of arguments, stopped";
  
  # Get arguments and set types
  my $arg_path = shift;
  my $arg_cmd  = shift;
  
  $arg_path = "$arg_path";
  $arg_cmd  = "$arg_cmd";
  
  # Get a redirection suffix
  my $redir_suf = "< \"$arg_path\"";
  
  # Edit the redirection suffix into the command
  if ($arg_cmd =~ /\|/) {
    $arg_cmd =~ s/\|/ $redir_suf \|/;
  } else {
    $arg_cmd = $arg_cmd . " $redir_suf";
  }
  
  # Open the pipeline in UTF-8
  open(my $fh_pipe, "-| :encoding(utf8)", $arg_cmd) or
    die "Failed to open pipeline '$arg_cmd', stopped";
  
  # Read lines from the pipeline
  while (my $pline = readline($fh_pipe)) {
    # Trim trailing line break if present
    if ($pline =~ /\r\n$/u) {
      # Strip CR+LF
      $pline = substr($pline, 0, -2);
      
    } elsif ($pline =~ /\n$/u) {
      # Strip LF
      $pline = substr($pline, 0, -1);
    }
    
    # Write the line
    write_line($pline);
  }
  
  # Close pipeline and check for error
  close($fh_pipe) or
    die "Pipeline failed: '$arg_cmd', stopped";
}

# ==================
# Program entrypoint
# ==================

# First off, set standard input and output to use UTF-8
#
binmode(STDIN, ":encoding(utf8)") or
    die "Failed to change standard input to UTF-8, stopped";
binmode(STDOUT, ":encoding(utf8)") or
  die "Failed to change standard output to UTF-8, stopped";

# Define variables to receive option values
#
my $has_style = 0;
my $style_path;

# Interpret program arguments
#
for(my $i = 0; $i <= $#ARGV; $i++) {
  if ($ARGV[$i] eq '-style') {
    ($i < $#ARGV) or die "-style option requires parameter, stopped";
    $i++;
    
    $has_style = 1;
    $style_path = $ARGV[$i];
    
    (-f $style_path) or
      die "Can't find style file '$style_path', stopped";
    
  } else {
    die "Unrecognized option '$ARGV[$i]', stopped";
  }
}

# Make sure we got the style path
#
($has_style) or die "-style option required, stopped";

# Slurp whole style sheet file in binary mode
#
open(my $fh_style, "< :raw", $style_path) or
  die "Failed to open style file '$style_path', stopped";

my $js_raw;
{
  local $/;
  $js_raw = readline($fh_style);
}

close($fh_style);

# Decode the JSON style sheet
#
my $js = decode_json($js_raw);

# Make sure JSON style sheet is reference to a hash
#
(ref($js) eq 'HASH') or
  die "JSON style file has invalid format, stopped";

# Read the first line from input, which must be a signature line (with
# optional UTF-8 BOM)
#
(my $first_line = <STDIN>) or die "Failed to read signature, stopped";
($first_line =~ /^(?:\x{feff})?`%bark[ \t\r\n]*$/u) or
  die "Bark signature line missing, stopped";

# Get a temporary file name for pipeline buffering and set an end
# handler to unlink it
#
my $tpath = tmpnam();
END {
  unlink $tpath;
}

# Read and interpret the rest of the lines
#
my $active_style = 0;
my $style_cmd;
my $fh_buf;

while (<STDIN>) {

  # Handle line type
  if (/^``/u) {
    # Escape line -- drop first character
    $_ = substr($_, 1);
    
    # Trim trailing line break if present
    if (/\r\n$/u) {
      # Strip CR+LF
      $_ = substr($_, 0, -2);
      
    } elsif (/\n$/u) {
      # Strip LF
      $_ = substr($_, 0, -1);
    }
    
    # If a style is active, add this line to buffer file; else, directly
    # output this line
    if ($active_style) {
      print {$fh_buf} "$_\n";
      
    } else {
      write_line($_);
    }

  } elsif ((/^`$/u) or (/^`[ \t\r\n]+/u)) {
    # Comment line -- skip
    next;
  
  } elsif (/^`:/u) {
    # Section command -- first we need to flush the buffered data if
    # there is currently a style active
    if ($active_style) {
      close($fh_buf);
      flush_pipeline($tpath, $style_cmd);
      $active_style = 0;
    }
    
    # Apply section connection
    section_connect();
    
    # Determine whether there is an active style after this command
    if (/^`:[ \t]*([A-Za-z0-9_]+)[ \t\r\n]*$/u) {
      $active_style = 1;
      my $sname = $1;
      (exists $js->{$sname}) or
        die "Can't find style '$sname' in style sheet, stopped";
      (not ref($js->{$sname})) or
        die "Invalid value for style '$sname' in style sheet, stopped";
      $style_cmd = "$js->{$sname}";
      
    } elsif (/^`:[ \t\r\n]*$/u) {
      $active_style = 0;
      
    } else {
      die "Invalid section command '$_', stopped";
    }
    
    # If a style is active, (re)create the buffer file
    if ($active_style) {
      open($fh_buf, "+> :encoding(utf8)", $tpath) or
        die "Failed to create temporary file, stopped";
    }
    
  } elsif (/^`+/u) {
    # Join command -- first we need to flush the buffered data if
    # there is currently a style active, and then adjust connection
    if ($active_style) {
      close($fh_buf);
      flush_pipeline($tpath, $style_cmd);
      $active_style = 0;
    }
    
    # Apply join connection
    join_connect();
    
    # Determine whether there is an active style after this command
    if (/^`\+[ \t]*([A-Za-z0-9_]+)[ \t\r\n]*$/u) {
      $active_style = 1;
      my $sname = $1;
      (exists $js->{$sname}) or
        die "Can't find style '$sname' in style sheet, stopped";
      (not ref($js->{$sname})) or
        die "Invalid value for style '$sname' in style sheet, stopped";
      $style_cmd = "$js->{$sname}";
      
    } elsif (/^`\+[ \t\r\n]*$/u) {
      $active_style = 0;
      
    } else {
      die "Invalid join command '$_', stopped";
    }
    
    # If a style is active, (re)create the buffer file
    if ($active_style) {
      open($fh_buf, "+> :encoding(utf8)", $tpath) or
        die "Failed to create temporary file, stopped";
    }
  
  } elsif ((length($_) < 1) or (/^[^`]/u)) {
    # Data line -- trim trailing line break if present
    if (/\r\n$/u) {
      # Strip CR+LF
      $_ = substr($_, 0, -2);
      
    } elsif (/\n$/u) {
      # Strip LF
      $_ = substr($_, 0, -1);
    }
    
    # If a style is active, add this line to buffer file; else, directly
    # output this line
    if ($active_style) {
      print {$fh_buf} "$_\n";
      
    } else {
      write_line($_);
    }

  } else {
    # Invalid line
    die "Invalid text line '$_', stopped";
  }
}

# Flush buffered data if style active at end of input
#
if ($active_style) {
  flush_pipeline($tpath, $style_cmd);
  close($fh_buf);
  $active_style = 0;
}

# Flush anything in the write buffer
#
write_flush();

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
