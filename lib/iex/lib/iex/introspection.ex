defmodule IEx.Introspection do
  # Convenience helpers for showing docs, specs and types
  # from modules. Invoked directly from IEX.Helpers.
  @moduledoc false

  import IEx, only: [dont_display_result: 0]

  @doc false
  def h(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      { :module, _ } ->
        if function_exported?(module, :__info__, 1) do
          case module.__info__(:moduledoc) do
            { _, binary } when is_binary(binary) ->
              IEx.ANSIDocs.print_heading(inspect module)
              IEx.ANSIDocs.print(binary)
            { _, _ } ->
              nodocs(inspect module)
            _ ->
              IO.puts IEx.color(:eval_error, "#{inspect module} was not compiled with docs")
          end
        else
          IO.puts IEx.color(:eval_error, "#{inspect module} is an Erlang module and, as such, it does not have Elixir-style docs")
        end
      { :error, reason } ->
        IO.puts IEx.color(:eval_error, "Could not load module #{inspect module}, got: #{reason}")
    end
    dont_display_result
  end

  def h(_) do
    IO.puts IEx.color(:eval_error, "Invalid arguments for h helper")
    dont_display_result
  end

  @doc false
  def h(modules, function) when is_list(modules) and is_atom(function) do
    result =
      Enum.reduce modules, :not_found, fn
        module, :not_found -> h_mod_fun(module, function)
        _module, acc -> acc
      end

    unless result == :ok, do:
      nodocs(function)

    dont_display_result
  end

  def h(module, function) when is_atom(module) and is_atom(function) do
    case h_mod_fun(module, function) do
      :ok ->
        :ok
      :no_docs ->
        IO.puts IEx.color(:eval_error, "#{inspect module} was not compiled with docs")
      :not_found ->
        nodocs("#{inspect module}.#{function}")
    end

    dont_display_result
  end

  def h(function, arity) when is_atom(function) and is_integer(arity) do
    h([IEx.Helpers, Kernel, Kernel.SpecialForms], function, arity)
    dont_display_result
  end

  def h(_, _) do
    IO.puts IEx.color(:eval_error, "Invalid arguments for h helper")
    dont_display_result
  end

  defp h_mod_fun(mod, fun) when is_atom(mod) and is_atom(fun) do
    if docs = mod.__info__(:docs) do
      result = lc { {f, arity}, _line, _type, _args, doc } inlist docs, fun == f, doc != false do
        h(mod, fun, arity)
        IO.puts ""
      end

      if result != [], do: :ok, else: :not_found
    else
      :no_docs
    end
  end

  @doc false
  def h(modules, function, arity) when is_list(modules) and is_atom(function) and is_integer(arity) do
    result =
      Enum.reduce modules, :not_found, fn
        module, :not_found -> h_mod_fun_arity(module, function, arity)
        _module, acc -> acc
      end

    unless result == :ok, do:
      nodocs("#{function}/#{arity}")

    dont_display_result
  end

  def h(module, function, arity) when is_atom(module) and is_atom(function) and is_integer(arity) do
    case h_mod_fun_arity(module, function, arity) do
      :ok ->
        :ok
      :no_docs ->
        IO.puts IEx.color(:eval_error, "#{inspect module} was not compiled with docs")
      :not_found ->
        nodocs("#{inspect module}.#{function}/#{arity}")
    end

    dont_display_result
  end

  def h(_, _, _) do
    IO.puts IEx.color(:eval_error, "Invalid arguments for h helper")
    dont_display_result
  end

  defp h_mod_fun_arity(mod, fun, arity) when is_atom(mod) and is_atom(fun) and is_integer(arity) do
    if docs = mod.__info__(:docs) do
      doc =
        cond do
          d = find_doc(docs, fun, arity)         -> d
          d = find_default_doc(docs, fun, arity) -> d
          true                                   -> nil
        end

      if doc do
        print_doc(doc)
        :ok
      else
        :not_found
      end
    else
      :no_docs
    end
  end

  defp find_doc(docs, function, arity) do
    if doc = List.keyfind(docs, { function, arity }, 0) do
      case elem(doc, 4) do
        false -> nil
        _ -> doc
      end
    end
  end

  defp find_default_doc(docs, function, min) do
    Enum.find docs, fn(doc) ->
      case elem(doc, 0) do
        { ^function, max } when max > min ->
          defaults = Enum.count elem(doc, 3), &match?({ ://, _, _ }, &1)
          min + defaults >= max
        _ ->
          false
      end
    end
  end

  defp print_doc({ { fun, _ }, _line, kind, args, doc }) do
    args = Enum.map_join(args, ", ", &print_doc_arg(&1))
    IEx.ANSIDocs.print_heading("#{kind} #{fun}(#{args})")
    if doc, do: IEx.ANSIDocs.print(doc)
  end

  defp print_doc_arg({ ://, _, [left, right] }) do
    print_doc_arg(left) <> " // " <> Macro.to_string(right)
  end

  defp print_doc_arg({ var, _, _ }) do
    atom_to_binary(var)
  end

  @doc false
  def t(module) do
    case Kernel.Typespec.beam_types(module) do
      nil   -> nobeam(module)
      []    -> notypes(inspect module)
      types -> lc type inlist types, do: print_type(type)
    end

    dont_display_result
  end

  @doc false
  def t(module, type) when is_atom(type) do
    case Kernel.Typespec.beam_types(module) do
      nil   -> nobeam(module)
      types ->
        printed =
          lc {_, {t, _, _args}} = typespec inlist types, t == type do
            print_type(typespec)
            typespec
          end

        if printed == [] do
          notypes("#{inspect module}.#{type}")
        end
    end

    dont_display_result
  end

  @doc false
  def t(module, type, arity) do
    case Kernel.Typespec.beam_types(module) do
      nil   -> nobeam(module)
      types ->
        printed =
          lc {_, {t, _, args}} = typespec inlist types, t == type, length(args) == arity do
            print_type(typespec)
            typespec
          end

        if printed == [] do
          notypes("#{inspect module}.#{type}")
        end
    end

    dont_display_result
  end

  @doc false
  def s(module) do
    case beam_specs(module) do
      nil   -> nobeam(module)
      []    -> nospecs(inspect module)
      specs -> lc spec inlist specs, do: print_spec(spec)
    end

    dont_display_result
  end

  @doc false
  def s(module, function) when is_atom(function) do
    case beam_specs(module) do
      nil   -> nobeam(module)
      specs ->
        printed =
          lc {_kind, {{f, _arity}, _spec}} = spec inlist specs, f == function do
            print_spec(spec)
            spec
          end

        if printed == [] do
          nospecs("#{inspect module}.#{function}")
        end
    end

    dont_display_result
  end

  @doc false
  def s(module, function, arity) do
    case beam_specs(module) do
      nil   -> nobeam(module)
      specs ->
        printed =
          lc {_kind, {{f, a}, _spec}} = spec inlist specs, f == function and a == arity do
            print_spec(spec)
            spec
          end

        if printed == [] do
          nospecs("#{inspect module}.#{function}")
        end
    end

    dont_display_result
  end

  defp beam_specs(module) do
    specs = Enum.map(Kernel.Typespec.beam_specs(module), &{:spec, &1})
    callbacks = Enum.map(Kernel.Typespec.beam_callbacks(module), &{:callback, &1})
    specs && callbacks && Enum.concat(specs, callbacks)
  end

  defp print_type({ kind, type }) do
    ast = Kernel.Typespec.type_to_ast(type)
    IO.puts IEx.color(:eval_info, "@#{kind} #{Macro.to_string(ast)}")
    true
  end

  defp print_spec({kind, { { name, _arity }, specs }}) do
    Enum.each specs, fn(spec) ->
      binary = Macro.to_string Kernel.Typespec.spec_to_ast(name, spec)
      IO.puts IEx.color(:eval_info, "@#{kind} #{binary}")
    end
    true
  end

  defp nobeam(module) do
    case Code.ensure_loaded(module) do
      { :module, _ } ->
        IO.puts IEx.color(:eval_error, "Beam code not available for #{inspect module} or debug info is missing, cannot load typespecs")
      { :error, reason } ->
        IO.puts IEx.color(:eval_error, "Could not load module #{inspect module}, got: #{reason}")
    end
  end

  defp nospecs(for), do: no(for, "specification")
  defp notypes(for), do: no(for, "type information")
  defp nodocs(for),  do: no(for, "documentation")

  defp no(for, type) do
    IO.puts IEx.color(:eval_error, "No #{type} for #{for} was found")
  end
end
