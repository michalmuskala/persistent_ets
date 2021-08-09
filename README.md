# PersistentEts

<!-- MDOC !-->

Ets table backed by a persistence file.

The table is persisted using the `:ets.file2tab/2` and `:ets.tab2file/3`
functions.

Table is to be created with `PersistentEts.new/3` in place of `:ets.new/2`.
After that all functions from `:ets` can be used like with any other table,
except `:ets.give_away/3` and `:ets.delete/1` - replacement functions are
provided in this module. The `:ets.setopts/2` function to change the heir
is not supported - the heir setting is leveraged by the persistence mechanism.

Like with regular ets table, the table is destroyed once the owning process
(the one that called `PersistentEts.new/3`) dies, but the table data is persisted
so it will be re-read when table is opened again.

## Example

```elixir
pid = spawn(fn ->
  :foo = PersistentEts.new(:foo, "table.tab", [:named_table])
  :ets.insert(:foo, [a: 1])
end)
Process.exit(pid, :diediedie)
PersistentEts.new(:foo, "table.tab", [:named_table])
[a: 1] = :ets.tab2list(:foo)
```

<!-- MDOC !-->

## Why not Dets?

With Dets every operation (read or write) hits the disk. For many application such a performance penalty (compared to ets) is not acceptable. Furthermore Dets tables are limited to 2GB. Dets doesn't support the `ordered_set` table type either.

With PersistentEts, the table remains in memory, so all read and write operations have the same performance they would have with pure Ets. Only periodically the table state is saved to a file. There's also no file limit, besides the memory and disk limitations. Since it's a regular Ets table, unlike with Dets, all types are fully supported.

## Installation

The package can be installed by adding `:persistent_ets` to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:persistent_ets, "~> 0.1.0"}
  ]
end
```

## Copyright and License

Copyright (c) 2017 Michał Muskała

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
