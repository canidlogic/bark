# Bark

Bark is a compound text format that allows you to apply different transformations to different parts of the same text.

## Bark text format

Bark text format must be a UTF-8 text file (US-ASCII is also OK since it is a strict subset of UTF-8).  A UTF-8 Byte Order Mark (BOM) may appear at the very start of the file, but it will be ignored.  Line breaks may either be LF or CR+LF.  If no line break appears at the end of the last line, a line break will be automatically inserted at the end.

The first line must be a signature line as follows:

    `%bark

Nothing may precede the opening grave accent (except the optional UTF-8 Byte Order Mark).  Spaces and tabs may optionally appear at the end of this signature line.  The signature is case sensitive.

All lines after the first line are divided into _data lines_, _escape lines_, and _bark lines_.  Lines that are empty or that have a character other than a grave accent as the first character in the line are data lines.  Lines that begin immediately with a sequence of __two__ or more grave accents are escape lines.  All other lines that begin immediately with a grave accent are bark lines.  No whitespace is allowed before the opening grave accent of escape lines or bark lines, otherwise they will be interpreted as data lines.

Escape lines are equivalent to a data line that starts with one less grave accent at the beginning of the line.  They are used to represent data lines that would otherwise be mistaken for bark line:

    ```This is an escape line that begins with two grave accents.

Bark lines are classified by what comes immediately after the opening grave accent.  If nothing comes immediately after the opening grave accent, or a space or tab comes immediately after the opening grave accent, the line is a _comment line_.  Everything in a comment line will be ignored and the file will be interpreted the same was as if the comment line were never present.  The only restriction is that no comment line may appear before the signature line at the start of the file:

    ` This is a comment line.

If a colon comes immediately after the opening grave accent, the bark line is a _section_ command.  There may optionally be a _style name_ after the colon on the bark line, which must be a sequence of one or more US-ASCII alphanumeric and underscore characters.  Whitespace is optional between the colon and the style name, and optional at the end of the line.  Here is an example of a section command without a style name:

    `:

Here is an example of a section command with a style name:

    `: example_style_name

If a plus sign comes immediately after the opening grave accent, the bark line is a _join_ command.  As with section commands, there may be an optional style name after the plus sign on the bark line.  Here is an example of a join command without a style name:

    `+

Here is an example of a join command with a style name:

    `+ example_style_name

## Bark file interpretation

Data lines and escape lines that occur before any section or join command are intended to be output as-is, except that escape lines have one less grave accent at the start of the line.

A section or join command allows the _style_ to be changed.  The only difference between the two commands is how the last data line before the command is connected to the first data line after the command.  For a section command, there is a line break between the two data lines, so that the new section begins on the next line in the output.  For a join command, there is no line break between the two data lines, so the data line after the join is on the same line as the data line before the join.  This allows there to be multiple style types on the same output line.

If no style name is provided on a section or join command, it means that subsequent data lines and escape lines are handled the same way as at the start of file, with no processing besides dropping a grave accent from the start of escape lines.

If a style name is provided on a section or join command, it means that subsequent data lines should be processed according to the named style.  The way these styles should be processed is defined in a separate file.

## Bark dispatch format

A _Bark dispatch file_ indicates how the different styles that are used in the Bark file should be processed.  A dispatch file is a JSON file.  The top-level entity must be a JSON object.  The properties of this object must be style names matching the names given in the Bark text format file.  The values of these properties must be strings containing a shell command establishing a processing pipeline.

Data lines affected by a style will be passed through the selected processing pipeline to transform them appropriately.  For escape lines, one grave accent will be dropped from the line before passing it through the processing pipeline.

The pipeline is always opened at a join or section command, even if there are no data lines after it.  This allows output generated by pipelines to be included within the Bark output.  Lines will be passed through until the end of the Bark text file, or the next join or section command (whichever comes first).  Each line passed into the pipeline will have a line break at the end of it.  Join commands will drop one line break from the end of whatever the last line was, unless there was no line break at the end of the last line, in which case they have no effect.  Section commands will insert nothing if the last line ended with a line break or if there was no last line.  If the last line did not end with a line break, a line break will be inserted.

At the very end of generated output, a line break will be inserted if none is present.
