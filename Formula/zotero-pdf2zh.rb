class ZoteroPdf2zh < Formula

  desc "Zotero PDF → ZH local server"
  homepage "https://github.com/guaguastandup/zotero-pdf2zh"
  url "https://github.com/guaguastandup/zotero-pdf2zh/releases/download/v3.0.37/server.zip"
  sha256 "e41b6b9d951034b74bc7407ba7faf5afe4a383accfa571c2fc9896cb189fb4c3"

  depends_on "uv"

  def install
    # Unzip the downloaded file and install the contents into libexec
    libexec.install Dir["*"]

    (bin/"zotero-pdf2zh").write <<~SH
      #!/usr/bin/env bash
      set -euo pipefail
      ROOT="#{opt_libexec}"
      DATA="#{var}/zotero-pdf2zh"
      VENV="$DATA/venv"
      MARKER="$DATA/needs-deps-update"
      SRC_CFG="$ROOT/config"
      DST_CFG="$DATA/config"
      UV="#{Formula["uv"].opt_bin}/uv"

      mkdir -p "$DST_CFG" "$DATA/translated"
      # Seed default config files into writable config dir (if missing).
      # IMPORTANT: Do NOT copy the `.example` files into the writable config dir.
      # Upstream will overwrite config files whenever `<file>.example` exists in `config/`.
      # By copying the example content into the real config filenames (and omitting `.example`),
      # we make config persistent across restarts/upgrades without patching upstream code.
      if [ -d "$SRC_CFG" ]; then
        for f in "$SRC_CFG"/*.example; do
          [ -f "$f" ] || continue
          base="$(basename "$f")"
          target="${base%.example}"
          if [ "$target" = "$base" ]; then
            continue
          fi
          if [ ! -f "$DST_CFG/$target" ]; then
            cp "$f" "$DST_CFG/$target"
          fi
        done
      fi
      # Link writable data into install tree and run
      cd "$ROOT"
      ln -snf "$DST_CFG" config
      ln -snf "$DATA/translated" translated
      
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
        cat >"$VENV/bin/pdf2zh_next" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SELF_DIR/python" -m pdf2zh_next "$@"
EOF
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
    chmod 0755, bin/"zotero-pdf2zh"

    (bin/"zotero-pdf2zh-update").write <<~SH
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
        cat >"$VENV/bin/pdf2zh_next" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SELF_DIR/python" -m pdf2zh_next "$@"
EOF
        chmod 0755 "$VENV/bin/pdf2zh_next"
      fi

      current="$("$VENV/bin/python" - <<'PY'
      try:
          import re
          from importlib import metadata

          def norm(name: str) -> str:
              return re.sub(r"[-_.]+", "-", name).lower()

          candidates = {norm("pdf2zh_next"), norm("pdf2zh-next")}
          found = None
          for dist in metadata.distributions():
              n = dist.metadata.get("Name") or dist.name
              if n and norm(n) in candidates:
                  found = dist
                  break

          if found is None:
              print("unknown")
          else:
              print(found.version)
      except Exception:
          print("unknown")
      PY
      )"

      # Snapshot current environment for rollback.
      "$UV" pip freeze -p "$VENV/bin/python" > "$REQ_PREV" || true

      # Refresh only when explicitly updating.
      "$UV" pip install -p "$VENV/bin/python" -U pdf2zh_next

      new="$("$VENV/bin/python" - <<'PY'
      try:
          import re
          from importlib import metadata

          def norm(name: str) -> str:
              return re.sub(r"[-_.]+", "-", name).lower()

          candidates = {norm("pdf2zh_next"), norm("pdf2zh-next")}
          found = None
          for dist in metadata.distributions():
              n = dist.metadata.get("Name") or dist.name
              if n and norm(n) in candidates:
                  found = dist
                  break

          if found is None:
              print("unknown")
          else:
              print(found.version)
      except Exception:
          print("unknown")
      PY
      )"

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
    chmod 0755, bin/"zotero-pdf2zh-update"
  end

  def post_install
    # Request a one-time dependency refresh after (re)install/upgrade.
    # This keeps normal service starts offline/fast, while still allowing
    # `brew upgrade` + service restart to pick up new PyPI releases.
    (var/"zotero-pdf2zh").mkpath
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
    # Ensure the wrapper is callable and prints help without starting the server
    system bin/"zotero-pdf2zh", "--help"
  end
end
