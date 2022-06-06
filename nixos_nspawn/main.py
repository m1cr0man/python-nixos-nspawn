import sys


def main(args: list[str]) -> int:
    import rich

    print("Hello world!")
    return 0


def main_with_args() -> int:
    return main(sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main_with_args())
