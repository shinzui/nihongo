# Width demo topic

This topic exists to demonstrate that long paragraphs are wrapped to the terminal
width or to an explicit `--width` value. When you pass `nihongo help width-demo
--width 40` you should see this paragraph reflow to roughly 40 columns. When you
pipe the output through a non-TTY consumer (for example, `nihongo help width-demo
| cat`) it should remain unwrapped, because byte-stable output is the right
behaviour for piped readers.

  this is a verbatim block
  it should not be reflowed
  regardless of width settings

A second paragraph follows the verbatim block to confirm that wrapping resumes for
plain prose.
