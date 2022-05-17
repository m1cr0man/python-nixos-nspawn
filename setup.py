#!/usr/bin/env bash
from os import path

from setuptools import find_packages, setup

with open(path.join(path.dirname(__file__), "nixos_nspawn/version.txt"), "r") as version_file:
    version = version_file.readline().strip()

# The README.md will be used as the long description
with open("README.md", "r") as readme:
    long_description = readme.read()

setup(
    name="nixos_nspawn",
    version=version,
    python_requires=">= 3.9, < 4",
    packages=find_packages(exclude=["tests", "tests.*"]),
    package_dir={"": "."},
    entry_points={
        "console_scripts": [
            # If you would like to change the name of the CLI program, change the
            # name on the left side of the equals.
            "nixos-nspawn=nixos_nspawn:main_with_args",
        ],
    },
    package_data={
        # If there are non-python files you need to include in the project, specify
        # them here. The format is like so:
        # ("nixos_nspawn.data", ["local_path/local_file", "local_path/local_file_2"]),
        # The result would be a module under our project called "data" that contains the 2
        # specified files
        "nixos_nspawn": ["version.txt"]
    },
    test_suite="tests",
    # Metadata for PyPI
    long_description=long_description,
    long_description_content_type="text/markdown",
    description="Rewrite of the Nix RFC 108 imperative container manager",
    url="https://github.com/m1cr0man/python-nixos-nspawn",
    project_urls={"Source": "https://github.com/m1cr0man/python-nixos-nspawn"},
    classifiers=[
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
    ],
)
