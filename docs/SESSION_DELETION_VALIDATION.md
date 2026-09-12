# Test session and CRD deletion

Use the dedicated `shadok-go-e2e` Kind cluster with the operator under test installed. Other sessions must be inactive. The test deletes the CRD and saves/restores the inactive fixtures.

From the repository root:

```sh
python3 operator-go/test/e2e/finalizer_lifecycle.py
```

Verify that all cases pass:

- Active session deletion and production restoration.
- External template edits preserved.
- Deployment recreated or already deleted.
- Session deletion with the operator stopped, followed by cleanup after restart.
- CRD deletion with an active session and the operator stopped.
- Cleanup after restart while the CRD is absent.
- Automatic handling of a session carrying `shadok.org/restore-baseline`.

After the test, check that the CRD and inactive fixtures are restored. For operational deletion commands, use `shadok learn lifecycle`.
