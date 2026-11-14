# Two root anchors in an entry file.
{
  outputs = _: {
    root = ../.;
    again = ./..;
  };
}
