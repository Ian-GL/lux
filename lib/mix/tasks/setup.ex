defmodule Mix.Tasks.Setup do
  @moduledoc """
  Sets up the project for local development.

  This task:
  1. Installs Elixir dependencies
  2. Ensures Poetry is installed and configured
  3. Create virtual env
  4. Installs Python dependencies

  ## Usage

      mix setup
  """
  use Mix.Task

  @shortdoc "Sets up the project for local development"
  @requirements []

  @default_poetry_paths [
    "~/.local/bin/poetry",
    "/usr/local/bin/poetry",
    "/opt/homebrew/bin/poetry"
  ]

  @priv_python_dir "priv/python"
  @priv_nodejs_dir "priv/node"

  defp safe_cmd(cmd, args, opts) do
    try do
      System.cmd(cmd, args, opts)
    rescue
      e in ErlangError ->
        case e do
          %ErlangError{original: :enoent} -> {:error, :not_found}
          _ -> reraise e, __STACKTRACE__
        end
    end
  end

  @impl Mix.Task
  def run(opts \\ []) do
    poetry_paths = Keyword.get(opts, :poetry_paths, @default_poetry_paths)

    with _ <- Mix.shell().info("\n==> Setting up Lux for development\n"),
         # Step 1: Install Elixir dependencies
         _ <- Mix.shell().info("==> Installing Elixir dependencies..."),
         :ok <- install_deps(),
         # Step 2: Check and setup Poetry
         _ <- Mix.shell().info("\n==> Checking Poetry installation..."),
         {:ok, poetry_path} <- find_poetry(poetry_paths),
         # Step 3: Setup Python virtual environment
         _ <- Mix.shell().info("\n==> Setting up Python virtual environment..."),
         :ok <- setup_virtualenv(),
         # Step 4: Install Python dependencies
         _ <- Mix.shell().info("\n==> Installing Python dependencies..."),
         :ok <- install_python_deps(poetry_path),
           # Step 5: Install Node.js dependencies
         Mix.shell().info("\n==> Installing Node.js dependencies..."),
         :ok <- install_nodejs_deps() do
      Mix.shell().info("""
      \n==> Setup completed successfully! 🎉

      You can now:
      • Activate the Python virtual environment:
          source priv/python/.venv/bin/activate

      • Run tests:
          mix test              # Run Elixir tests
          mix python.test       # Run Python tests

      • Generate documentation:
          mix docs

      • Start development:
          iex -S mix
      """)
    else
      _ ->
        exit({:shutdown, 1})
    end
  end

  defp find_poetry(paths) do
    # Check common Poetry installation paths
    poetry_path =
      Enum.find(paths, fn path ->
        path = Path.expand(path)
        File.exists?(path)
      end)

    if poetry_path do
      Mix.shell().info("Found Poetry at: #{poetry_path}")
      {:ok, Path.expand(poetry_path)}
    else
      Mix.shell().error("Poetry not found")

      Mix.shell().error("""
      Please try manually:

      1. Install Poetry:
          curl -sSL https://install.python-poetry.org | python3 -

      2. Add to your PATH by adding this line to ~/.zshrc or ~/.bashrc:
          export PATH="$HOME/.local/bin:$PATH"

      3. Reload your shell:
          source ~/.zshrc  # or source ~/.bashrc

      Then run `mix setup` again.
      """)

      exit({:shutdown, 0})
    end
  end

  defp install_deps() do
    case safe_cmd("mix", ["deps.get"], into: IO.stream()) do
      {:error, :not_found} ->
        Mix.raise("Could not find 'mix' command")

      {_, 0} ->
        :ok

      {output, _} ->
        Mix.raise("Failed to install dependencies: #{output}")
    end
  end

  defp setup_virtualenv() do
    venv_path = [@priv_python_dir, ".venv"] |> Path.join() |> Path.expand()

    with false <- File.exists?(venv_path),
         {output, 0} <- safe_cmd("python3", ["-m", "venv", venv_path], stderr_to_stdout: true) do
      Mix.shell().info(output)
      :ok
    else
      true ->
        Mix.shell().info("Python virtual environment at: #{venv_path}")
        :ok

      {:error, :not_found} ->
        Mix.shell().error("Python is required to setup the virtual environment")
        exit({:shutdown, 1})

      {output, _} ->
        Mix.shell().error("Failed to setup Python virtual environment: #{output}")
        exit({:shutdown, 1})
    end
  end

  defp install_python_deps(poetry_path) do
    python_dir = Path.join(File.cwd!(), @priv_python_dir)

    case safe_cmd(poetry_path, ["install"], cd: python_dir, stderr_to_stdout: true) do
      {:error, :not_found} ->
        Mix.shell().error("\nFailed to execute Poetry command")

        Mix.shell().error("""

        Try these steps to resolve the issue:
        1. Make sure Poetry is properly installed:
            poetry --version
        2. If needed, update Poetry:
            poetry self update
        3. Try clearing Poetry's cache:
            poetry cache clear . --all
        4. Run setup again:
            mix setup
        """)

        exit({:shutdown, 1})

      {output, 0} ->
        Mix.shell().info(output)
        :ok

      {output, _} ->
        Mix.shell().error("\nFailed to install Python dependencies:\n\n#{output}")

        Mix.shell().error("""

        Try these steps to resolve the issue:
        1. Clear Poetry's cache:
            cd priv/python && poetry cache clear . --all
        2. Delete the poetry.lock file (if it exists):
            rm priv/python/poetry.lock
        3. Update Poetry itself:
            poetry self update
        4. Run setup again:
            mix setup

        If the issue persists, please check the error message above for specific dependency conflicts.
        You may need to manually resolve version conflicts in priv/python/pyproject.toml.
        """)

        exit({:shutdown, 1})
    end
  end

  defp install_nodejs_deps() do
    nodejs_dir = Path.join(File.cwd!(), @priv_nodejs_dir)

    case safe_cmd("npm", ["install"], cd: nodejs_dir, stderr_to_stdout: true) do
      {:error, :not_found} ->
        Mix.shell().error("\nFailed to execute npm command")

        Mix.shell().error("""

        Try these steps to resolve the issue:
        1. Make sure npm is properly installed:
            npm --version
        2. If needed, update npm:
            npm install -g npm
        3. Run setup again:
            mix setup
        """)

        exit({:shutdown, 1})

      {output, 0} ->
        Mix.shell().info(output)
        :ok

      {output, _} ->
        Mix.shell().error("\nFailed to install Node.js dependencies:\n\n#{output}")

        Mix.shell().error("""

        Try these steps to resolve the issue:
        1. Clear the node_modules directory:
            rm -rf priv/node/node_modules
        2. Run setup again:
            mix setup

        If the issue persists, please check the error message above for specific dependency conflicts.
        You may need to manually resolve version conflicts in priv/node/package.json.
        """)

        exit({:shutdown, 1})
    end
  end
end
