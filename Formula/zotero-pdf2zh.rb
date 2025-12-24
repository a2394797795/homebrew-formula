class ZoteroPdf2zh < Formula

  desc "Zotero PDF → ZH local server"
  homepage "https://github.com/guaguastandup/zotero-pdf2zh"
  url "https://github.com/guaguastandup/zotero-pdf2zh/releases/download/v3.0.37/server.zip"
  sha256 "e41b6b9d951034b74bc7407ba7faf5afe4a383accfa571c2fc9896cb189fb4c3"
  revision 1

  depends_on "uv"

  def install
    # Install upstream files into libexec.
    #
    # NOTE: `brew reinstall` may reuse the existing keg path; ensure we don't keep any
    # leftover runtime-generated files from prior installs.
    rm_rf libexec
    libexec.mkpath

    # Keep upstream example files, but do not leave them in the runtime config dir.
    # Upstream overwrites config files whenever `<file>.example` exists in `config/`.
    templates = libexec/"config_templates"
    rm_rf templates
    templates.mkpath
    if (buildpath/"config").directory?
      templates.install Dir["config/*"]
    else
      odie "Upstream archive is missing the expected `config/` directory"
    end

    # Install everything except the upstream config/translated dirs (we replace them with symlinks into `var`).
    to_install = Dir["*"] - ["__MACOSX", "config", "translated", "server.zip"]
    libexec.install to_install

    replace_with_symlink = lambda do |link, target|
      if link.symlink? || link.file?
        link.unlink
      elsif link.directory?
        rm_rf link
      elsif link.exist?
        rm_f link
      end
      ln_s target, link
    end

    # Persist user data/config outside the Cellar.
    replace_with_symlink.call(libexec/"config", var/"zotero-pdf2zh/config")
    replace_with_symlink.call(libexec/"translated", var/"zotero-pdf2zh/translated")

    wrapper = buildpath/"zotero-pdf2zh"
    wrapper.write <<~SH
      #!/usr/bin/env bash
      set -euo pipefail
      ROOT="#{opt_libexec}"
      DATA="#{var}/zotero-pdf2zh"
      VENV="$DATA/venv"
      MARKER="$DATA/needs-deps-update"
      UV="#{Formula["uv"].opt_bin}/uv"

      mkdir -p "$DATA/config" "$DATA/translated"
      cd "$ROOT"

      # Keep startup deterministic: don't upgrade dependencies on every start.
      # We only create the environment once, and only upgrade when explicitly requested
      # (e.g., after a `brew upgrade`, via the marker file).
      install_base_deps() {
        if [ -f "$ROOT/requirements.txt" ]; then
          "$UV" pip install -p "$VENV/bin/python" -r "$ROOT/requirements.txt"
        else
          "$UV" pip install -p "$VENV/bin/python" flask toml pypdf PyMuPDF packaging pdf2zh_next
        fi
      }

      ensure_pdf2zh_next_cli() {
        # The upstream server invokes `pdf2zh_next` as a subprocess. Ensure it's on PATH.
        export PATH="$VENV/bin:$PATH"
        if [ -x "$VENV/bin/pdf2zh_next" ]; then
          return 0
        fi
        if [ -x "$VENV/bin/pdf2zh-next" ]; then
          ln -snf "$VENV/bin/pdf2zh-next" "$VENV/bin/pdf2zh_next"
          return 0
        fi
        printf '%s\n' \
          '#!/usr/bin/env bash' \
          'set -euo pipefail' \
          'SELF_DIR="$(cd "$(dirname "$0")" && pwd)"' \
          'exec "$SELF_DIR/python" -m pdf2zh_next "$@"' \
          >"$VENV/bin/pdf2zh_next"
        chmod 0755 "$VENV/bin/pdf2zh_next"
      }

      if [ ! -x "$VENV/bin/python" ]; then
        mkdir -p "$DATA"
        "$UV" venv --python 3.12 "$VENV"
        install_base_deps
      fi
      ensure_pdf2zh_next_cli

      if [ -f "$MARKER" ]; then
        echo "Dependency update requested (marker found). Attempting update..."
        "#{opt_bin}/zotero-pdf2zh-update" --no-restart || echo "Dependency update failed; continuing with existing environment."
      fi

      # Disable upstream virtualenv manager and rely on the venv we manage here.
      # The upstream manager expects to create per-engine venvs under the install directory, which
      # is fragile under Homebrew. We instead ensure the `pdf2zh_next` CLI is available via PATH.
      exec "$VENV/bin/python" server.py --enable_venv false --check_update false "$@"
        SH
    wrapper.chmod 0755
    bin.install wrapper
    (bin/"zotero-pdf2zh").chmod 0755

    updater = buildpath/"zotero-pdf2zh-update"
    updater.write <<~SH
      #!/usr/bin/env bash
      set -euo pipefail
      RESTART=1
      if [ "${1:-}" = "--no-restart" ]; then
        RESTART=0
        shift
      elif [ "${1:-}" = "--restart" ]; then
        RESTART=1
        shift
      fi

      ROOT="#{opt_libexec}"
      DATA="#{var}/zotero-pdf2zh"
      VENV="$DATA/venv"
      MARKER="$DATA/needs-deps-update"
      UV="#{Formula["uv"].opt_bin}/uv"
      REQ_PREV="$DATA/requirements.prev.txt"

      mkdir -p "$DATA"
      cd "$ROOT"

      # Ensure environment exists (but don't upgrade on service start).
      install_base_deps() {
        if [ -f "$ROOT/requirements.txt" ]; then
          "$UV" pip install -p "$VENV/bin/python" -r "$ROOT/requirements.txt"
        else
          "$UV" pip install -p "$VENV/bin/python" flask toml pypdf PyMuPDF packaging pdf2zh_next
        fi
      }

      if [ ! -x "$VENV/bin/python" ]; then
        "$UV" venv --python 3.12 "$VENV"
        install_base_deps
      fi

      # Make sure we have all baseline deps that the upstream server expects.
      install_base_deps

      # Ensure the CLI is available for the upstream server's subprocess calls.
      export PATH="$VENV/bin:$PATH"
      if [ ! -x "$VENV/bin/pdf2zh_next" ] && [ -x "$VENV/bin/pdf2zh-next" ]; then
        ln -snf "$VENV/bin/pdf2zh-next" "$VENV/bin/pdf2zh_next"
      elif [ ! -x "$VENV/bin/pdf2zh_next" ]; then
        printf '%s\n' \
          '#!/usr/bin/env bash' \
          'set -euo pipefail' \
          'SELF_DIR="$(cd "$(dirname "$0")" && pwd)"' \
          'exec "$SELF_DIR/python" -m pdf2zh_next "$@"' \
          >"$VENV/bin/pdf2zh_next"
        chmod 0755 "$VENV/bin/pdf2zh_next"
      fi

      PYCODE=$'try:\n    import re\n    from importlib import metadata\n\n    def norm(name: str) -> str:\n        return re.sub(r\"[-_.]+\", \"-\", name).lower()\n\n    candidates = {norm(\"pdf2zh_next\"), norm(\"pdf2zh-next\")}\n    version = \"unknown\"\n    for dist in metadata.distributions():\n        n = (dist.metadata.get(\"Name\") or dist.name or \"\")\n        if n and norm(n) in candidates:\n            version = dist.version\n            break\n    print(version)\nexcept Exception:\n    print(\"unknown\")\n'

      current="$("$VENV/bin/python" -c "$PYCODE")"

      # Snapshot current environment for rollback.
      "$UV" pip freeze -p "$VENV/bin/python" > "$REQ_PREV" || true

      # Refresh only when explicitly updating.
      "$UV" pip install -p "$VENV/bin/python" -U pdf2zh_next

      new="$("$VENV/bin/python" -c "$PYCODE")"

      echo "pdf2zh_next: ${current} -> ${new}"

      health_check() {
        "$UV" pip check -p "$VENV/bin/python"
        "$VENV/bin/python" -c "import pdf2zh_next"
        "$VENV/bin/python" server.py --help >/dev/null
      }

      if ! health_check >/dev/null 2>&1; then
        echo "Health check failed after update; attempting rollback..."
        if [ -s "$REQ_PREV" ]; then
          "$UV" pip sync -p "$VENV/bin/python" "$REQ_PREV" >/dev/null
        fi
        if health_check >/dev/null 2>&1; then
          echo "Rollback succeeded; not restarting."
          rm -f "$MARKER"
          exit 1
        fi
        echo "Rollback failed; leaving environment as-is and not restarting."
        rm -f "$MARKER"
        exit 1
      fi

      rm -f "$MARKER"

      if [ "$current" != "$new" ]; then
        if [ "$RESTART" -eq 1 ] && command -v brew >/dev/null 2>&1; then
          brew services restart zotero-pdf2zh
        elif [ "$RESTART" -eq 1 ]; then
          echo "brew not found; please restart the service manually."
        else
          echo "Restart suppressed (--no-restart)."
        fi
      else
        echo "No change; not restarting."
      fi
    SH
    updater.chmod 0755
    bin.install updater
    (bin/"zotero-pdf2zh-update").chmod 0755
  end

  def post_install
    data = var/"zotero-pdf2zh"
    config = data/"config"
    config.mkpath
    (data/"translated").mkpath

    # Remove any `.example` files from the writable config directory.
    # If they exist, upstream will overwrite the real config files on every start.
    config.glob("**/*.example").each(&:unlink)

    # Seed default config files into a writable location (if missing).
    #
    # IMPORTANT: Do NOT copy the `.example` files into the writable config dir.
    # Upstream overwrites config files whenever `<file>.example` exists in `config/`.
    templates = opt_libexec/"config_templates"
    if templates.directory?
      templates.glob("**/*.example").each do |ex|
        next if ex.directory?
        rel = ex.relative_path_from(templates).to_s.sub(/\.example\z/, "")
        target = config/rel
        next if target.exist?
        target.dirname.mkpath
        target.write ex.read
      end
    end

    # Request a one-time dependency refresh after (re)install/upgrade.
    # This keeps normal service starts offline/fast, while still allowing
    # `brew upgrade` + service restart to pick up new PyPI releases.
    (var/"zotero-pdf2zh/needs-deps-update").atomic_write("1\n")
  end

  service do
    # Use the wrapper and default to the port used in run.sh
    run [opt_bin/"zotero-pdf2zh", "--port", "47700", "--check_update", "false"]
    keep_alive true
    working_dir opt_libexec
    log_path var/"log/zotero-pdf2zh.log"
    error_log_path var/"log/zotero-pdf2zh.log"
  end

  test do
    assert_predicate bin/"zotero-pdf2zh", :executable?
    assert_predicate bin/"zotero-pdf2zh-update", :executable?
    assert_match "#!/usr/bin/env bash", (bin/"zotero-pdf2zh").readlines.first.to_s
    assert_match "#!/usr/bin/env bash", (bin/"zotero-pdf2zh-update").readlines.first.to_s
    system "bash", "-n", bin/"zotero-pdf2zh"
    system "bash", "-n", bin/"zotero-pdf2zh-update"

    assert_predicate opt_libexec/"config_templates", :directory?
    assert_predicate opt_libexec/"config", :symlink?
    assert_predicate opt_libexec/"translated", :symlink?
  end
end
