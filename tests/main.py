import unittest

import nixos_nspawn


class CommandTest(unittest.TestCase):
    def test_help(self) -> None:
        self.assertEqual(
            0,
            nixos_nspawn.main(["nixos-nspawn", "--help"]),
            msg="Non-0 exit status with --help argument",
        )
