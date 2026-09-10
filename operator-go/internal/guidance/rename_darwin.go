package guidance

import "golang.org/x/sys/unix"

func renameNew(old, new string) error { return unix.RenamexNp(old, new, unix.RENAME_EXCL) }
