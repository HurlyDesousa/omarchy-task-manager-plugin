# Task Manager

CPU, GPU, RAM, thermals, fan meters, and a process table in an Omarchy bar popout.

Plugin id: `sw.art.task-manager`

## Install

```sh
omarchy plugin add https://github.com/HurlyDesousa/omarchy-task-manager-plugin.git --enable
```

Place it on the bar if needed:

```sh
omarchy bar move sw.art.task-manager --section center
```

## Usage

Click the `󰓅` icon to open or close the panel. Press Escape to close it.

- Compact view shows CPU, GPU, RAM, uptime, and fans
- **Processes** expands the searchable process table
- End process sends SIGTERM, then SIGKILL if needed
- Settings remember compact/expanded state and refresh interval

Stats come from the bundled `omarchy-task-manager` helper in this plugin folder. Python 3 is required. Fan RPM is read-only via `x1e-ec-tool` when that binary is present (Snapdragon X Elite); otherwise the fan rows show an em dash.

## Remove

```sh
omarchy plugin remove sw.art.task-manager
```

This only removes the plugin files. It does not change other Omarchy settings.

## License

MIT. See [LICENSE](LICENSE).
