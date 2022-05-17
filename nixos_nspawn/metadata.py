import os

with open(os.path.join(os.path.dirname(__file__), "version.txt"), "r") as version_file:
    version = version_file.readline().strip()
