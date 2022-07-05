from configparser import ConfigParser
from typing import IO, Any, Union


class SystemdSettings(dict):
    def __setitem__(self, key: str, value: Any) -> None:  # noqa: ANN401
        # Systemd allows a key to be specified multiple times, and all values
        # are combined into a list of values. This function handles that.
        if isinstance(value, list) and len(value) == 1:
            # By default, when reading a config file ConfigParser will
            # read each value into a list of strings then run _join_multiline_values
            # to iterate + join each list into a single string.
            # With systemd configs, we can immediately turn these first lines
            # into the actual values. Then we can store actual multi-value keys
            # in a list.
            value = value[0]

        if key in self:
            existing: Union[Any, list] = self[key]

            if isinstance(existing, list):
                # > 1 value already exist
                existing.append(value)
                value = existing

            else:
                # == 1 value already exists
                value = [existing, value]

        super(SystemdSettings, self).__setitem__(key, value)


class SystemdUnitParser(ConfigParser):
    def __init__(self, *args: Any, **kwargs: Any) -> None:  # noqa: ANN401
        return super(SystemdUnitParser, self).__init__(
            *args,
            dict_type=SystemdSettings,
            strict=False,
            empty_lines_in_values=False,
            interpolation=None,
            **kwargs,
        )

    def _join_multiline_values(self) -> None:
        # Not allowed in Systemd units, so don't ever do this.
        pass

    def optionxform(self, optionstr: str) -> str:
        # By default, calls .lower() on each option.
        # We want to preserve case.
        return optionstr

    def _write_section(
        self,
        fp: IO[str],
        section_name: str,
        section_items: list[tuple[str, Union[str, list[str]]]],
        delimiter: str,
    ) -> None:
        # Overridden to add support for multi-value fields.
        # Note: Removed interpolator support, as it's unneeded.
        fp.write(f"[{section_name}]\n")

        def write_value(k: str, val: str) -> None:
            # Indent multiline values for correct parsing
            val = str(val).replace("\n", "\n\t")
            fp.write(f"{k}{delimiter}{val}\n")

        for key, value in section_items:
            if isinstance(value, list):
                for subval in value:
                    write_value(key, subval)
            elif value is None:
                write_value(key, "")
            else:
                write_value(key, value)

        # Blank line between sections
        fp.write("\n")
