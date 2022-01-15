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

The only difference between a section command and a join command is that a line break is inserted between the previous section and the new section, while a join command does not add any line break.  The join command therefore allows multiple styles to be used on a single line of text that will be rendered in output.  There is no difference between a section command and a join command if they are used before anything has been output, since there is no previous section in that case to separate with a line break.

## Bark scripts

The first step in Bark processing is to transform a Bark text format file into a special multi-part MIME format message.  This is done by passing the Bark text format file through the `barkmime.pl` script.  The output of this script is in the multi-part MIME format message.  (See the documentation in `barkmime.pl` for the specifics of this format.)

Once you have the MIME message stored in a file, you can use this file in pipelines to transform specific text styles.  Each of these transformation pipelines begins with the `barkecho.pl` script, which takes the MIME message as input and also has a `-style` parameter that selects which style is being transformed (or a hyphen to transform style-less text).  The output of this script is in a simple text format that looks like this:

    <?bark_EkqoXaNiFIa?>
    Some text here.
    Continues on another line.
    <?bark_EkqoXaNiFIa?>
    Another section to process here.
    <?bark_EkqoXaNiFIa?>

The first line defines a special separator line, which always begins with `<?bark_` and ends with `?>` but the other characters are randomly selected.  The separator line is exactly the same throughout this text stream, and always occurs by itself on a line in order to be interpreted as a separator line.  The file always ends with one final separator line.

The text stream only includes text of the style selected by the `barkecho.pl` script at the start of the pipeline.  It can then be transformed by any kind of text transformation utility, provided that the separator lines are left as-is.

After transformation is complete, the pipeline ends with the `barkmerge.pl` script.  This script reads the transformed text stream as input and also takes a `-style` parameter that should match the `-style` parameter that was passed to the script at the start of the pipeline.  Finally, the script takes a `-msg` parameter that has the path to the MIME message that was read at the start of the pipeline.  This merger script reads all the incoming data and then creates a new version of the MIME message with all content of the selected style replaced by data coming in from the transformed text stream.  This new version of the MIME message then overwrites the old version of the MIME message.

This architecture allows different text styles to be processed with different text pipelines.  Since each pipeline handles all text of a given style, the total number of processing pipelines is equal to the total number of different styles that need to be processed.  Once the MIME message has been completely transformed, the `barkecho.pl` script is used one last time without any parameters, which renders all the transformed text in a single text stream.

Example of using the Bark scripts:

    barkmime.pl < input.btf > input.msg
    barkecho.pl -style - < input.msg | ... | barkmerge.pl -style - -msg input.msg
    barkecho.pl -style style1 < input.msg | ... | barkmerge.pl -style style1 -msg input.msg
    barkecho.pl -style style2 < input.msg | ... | barkmerge.pl -style style2 -msg input.msg
    ...
    barkecho.pl < input.msg > result.txt
