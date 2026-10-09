-- Konfigurace luacheck (linter ve VSCode): globály Factoria, aby editor nehlásil falešná varování.
std = "lua52"
max_line_length = 140
globals = { "storage", "data" }
read_globals = {
  "game", "script", "defines", "prototypes", "settings", "remote", "rendering", "helpers",
  "commands", "log", "serpent", "table_size", "mods", "localised_print",
  table = { fields = { "deepcopy" } },
}
files["tests/unit"] = { std = "lua53" }
