def _check50_escape_dependencies(dependencies):
    escaped_dependencies = []
    for dependency in dependencies:
        if (
            not isinstance(dependency, str)
            or not dependency.strip()
            or any(
                ord(character) < 0x20
                or 0x7F <= ord(character) <= 0x9F
                for character in dependency
            )
        ):
            raise _exceptions.Error(
                _(
                    "check dependency must be a non-empty string without "
                    "control characters"
                )
            )
        escaped_dependencies.append(
            '  "{}",'.format(
                dependency.replace("\\", "\\\\").replace('"', '\\"')
            )
        )
    return escaped_dependencies


def _check50_create_dependency_environment():
    try:
        temporary_directory = tempfile.TemporaryDirectory(
            prefix="check50-dependencies-"
        )
    except Exception as error:
        raise _exceptions.Error(
            _("failed to create a temporary dependency environment")
        ) from error
    return temporary_directory


def _check50_retain_dependency_environment(temporary_directory):
    if not hasattr(install_dependencies, "_temporary_directories"):
        install_dependencies._temporary_directories = []
    install_dependencies._temporary_directories.append(temporary_directory)


def _check50_write_dependency_project(project_file, escaped_dependencies):
    requires_python = f">={sys.version_info.major}.{sys.version_info.minor}"
    project_contents = (
        "[project]\n"
        'name = "check50-dynamic-dependencies"\n'
        'version = "0.0.0"\n'
        f'requires-python = "{requires_python}"\n'
        "dependencies = [\n"
        + "\n".join(escaped_dependencies)
        + "\n]\n"
    )
    try:
        project_file.write_text(project_contents, encoding="utf-8")
    except Exception as error:
        raise _exceptions.Error(
            _("failed to write the dynamic dependency project file")
        ) from error


def _check50_build_uv_environment(project_dir, virtual_environment):
    # Check definitions are a code trust boundary; do not pass caller
    # credentials or writable project tool directories to their builds.
    inherited = os.environ
    allowed_variables = (
        "LANG",
        "LC_ALL",
        "LC_CTYPE",
        "SSL_CERT_FILE",
        "SSL_CERT_DIR",
    )
    environment = {
        name: inherited[name] for name in allowed_variables if name in inherited
    }
    trusted_path_prefixes = (
        "/nix/store/",
        "/bin/",
        "/usr/bin/",
        "/usr/local/bin/",
        "/run/current-system/sw/bin/",
    )
    path_entries = [
        path
        for path in inherited.get("PATH", "").split(os.pathsep)
        if path
        and any(
            path == prefix[:-1] or path.startswith(prefix)
            for prefix in trusted_path_prefixes
        )
    ]
    if not path_entries:
        path_entries = [str(Path(sys.executable).parent)]
    environment["PATH"] = os.pathsep.join(dict.fromkeys(path_entries))
    state_dir = inherited.get("CS50_STATE_DIR")
    cache_dir = (
        Path(state_dir) / "uv-cache" if state_dir else project_dir / "uv-cache"
    )
    environment.update(
        HOME=str(project_dir),
        TMPDIR=str(project_dir),
        UV_CACHE_DIR=str(cache_dir),
        VIRTUAL_ENV=str(virtual_environment),
    )
    return environment


def _check50_get_uv_executable():
    configured_executable = os.environ.get("CS50_UV")
    if not configured_executable:
        return "uv"
    if not os.path.isabs(configured_executable) or not os.access(
        configured_executable, os.X_OK
    ):
        raise _exceptions.Error(
            _("CS50_UV must name an executable absolute path")
        )
    return configured_executable


def _check50_run_uv(project_dir, virtual_environment):
    environment = _check50_build_uv_environment(
        project_dir, virtual_environment
    )
    command = [
        _check50_get_uv_executable(),
        "sync",
        "--project",
        str(project_dir),
        "--no-dev",
        "--no-install-project",
        "--python",
        sys.executable,
    ]
    try:
        subprocess.run(
            command,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=environment,
            cwd=str(project_dir),
        )
    except FileNotFoundError as error:
        raise _exceptions.Error(
            _("failed to run uv: the uv executable was not found")
        ) from error
    except subprocess.CalledProcessError as error:
        raise _exceptions.Error(
            _("uv failed to install check dependencies (exit code {})").format(
                error.returncode
            )
        ) from error
    except OSError as error:
        raise _exceptions.Error(
            _("failed to run uv to install check dependencies")
        ) from error


def _check50_find_site_packages(virtual_environment):
    try:
        site_packages = next(
            virtual_environment.glob("lib/python*/site-packages"), None
        )
        if site_packages is None:
            error = FileNotFoundError(str(virtual_environment))
            raise _exceptions.Error(
                _("uv did not create a usable dependency environment")
            ) from error
        if not site_packages.is_dir():
            error = NotADirectoryError(str(site_packages))
            raise _exceptions.Error(
                _("uv did not create a usable dependency environment")
            ) from error
        return site_packages
    except _exceptions.Error:
        raise
    except Exception as error:
        raise _exceptions.Error(
            _("failed to inspect the uv dependency environment")
        ) from error


def _check50_activate_dependency_environment(
    site_packages, virtual_environment
):
    site_packages_path = str(site_packages)
    virtual_environment_bin = str(virtual_environment / "bin")
    original_sys_path = list(sys.path)
    original_path = os.environ.get("PATH")
    original_virtual_env = os.environ.get("VIRTUAL_ENV")
    try:
        site.addsitedir(site_packages_path)
        sys.path[:] = [
            path for path in sys.path if path != site_packages_path
        ]
        sys.path.insert(0, site_packages_path)
        path_entries = (
            [] if not original_path else original_path.split(os.pathsep)
        )
        path_entries = [
            path for path in path_entries if path != virtual_environment_bin
        ]
        os.environ["PATH"] = os.pathsep.join(
            [virtual_environment_bin] + path_entries
        )
        os.environ["VIRTUAL_ENV"] = str(virtual_environment)
    except Exception as error:
        sys.path[:] = original_sys_path
        if original_path is None:
            os.environ.pop("PATH", None)
        else:
            os.environ["PATH"] = original_path
        if original_virtual_env is None:
            os.environ.pop("VIRTUAL_ENV", None)
        else:
            os.environ["VIRTUAL_ENV"] = original_virtual_env
        raise _exceptions.Error(
            _("failed to activate the uv dependency environment")
        ) from error


def install_dependencies(dependencies):
    """Install check dependencies in a temporary uv environment."""
    if not dependencies:
        return

    escaped_dependencies = _check50_escape_dependencies(dependencies)
    temporary_directory = _check50_create_dependency_environment()
    _check50_retain_dependency_environment(temporary_directory)
    project_dir = Path(temporary_directory.name)
    _check50_write_dependency_project(
        project_dir / "pyproject.toml", escaped_dependencies
    )
    virtual_environment = project_dir / ".venv"
    _check50_run_uv(project_dir, virtual_environment)
    site_packages = _check50_find_site_packages(virtual_environment)
    _check50_activate_dependency_environment(
        site_packages, virtual_environment
    )
    LOGGER.info(
        _("installed {} check dependencies with uv").format(
            len(escaped_dependencies)
        )
    )


