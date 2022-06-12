from configparser import ConfigParser
from typing import IO, Any, Union


class SystemdSettings(dict):
    def __setitem__(self, key: str, value: Any) -> None:  # noqa: ANN401
        # Systemd allows a key to be specified multiple times, and all values
        # are combined into a list of values. This function handles that.
        if key in self:
            existing: Union[Any, list] = self[key]

            # > 1 value already exist
            if type(existing) == list:
                existing.append(value)
                return

            # == 1 value already exists
            value = [existing, value]

        super(SystemdSettings, self).__setitem__(key, value)


class SystemdUnitParser(ConfigParser):
    def __init__(self, *args: Any, **kwargs: Any) -> None:  # noqa: ANN401
        return super(SystemdUnitParser, self).__init__(
            *args,
            dict_type=SystemdSettings,
            strict=False,
            interpolation=None,
            **kwargs,
        )

    def _join_multiline_values(self) -> None:
        # Not allowed in Systemd units, so don't ever do this.
        pass

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
            fp.write(f"{k}{delimiter}{value}\n")

        for key, value in section_items:
            if isinstance(value, list):
                for subval in value:
                    write_value(key, subval)
            elif value is None:
                write_value(key, "")
            else:
                write_value(key, value)

        # Blank line between sections
        fp.write("\n\n")
