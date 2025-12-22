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
      # Seed example config files into writable config dir (if missing)
      if [ -d "$SRC_CFG" ]; then
        for f in "$SRC_CFG"/*.example; do
          [ -f "$f" ] || continue
          base="$(basename "$f")"
          if [ ! -f "$DST_CFG/$base" ]; then
            cp "$f" "$DST_CFG/$base"
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
      if [ ! -x "$VENV/bin/python" ]; then
        mkdir -p "$DATA"
        "$UV" venv --python 3.12 "$VENV"
        "$UV" pip install -p "$VENV/bin/python" flask toml pypdf PyMuPDF packaging pdf2zh_next
      fi

      if [ -f "$MARKER" ]; then
        echo "Dependency update requested (marker found). Attempting update..."
        if "#{opt_bin}/zotero-pdf2zh-update" --no-restart; then
          rm -f "$MARKER"
        else
          echo "Dependency update failed; continuing with existing environment."
        fi
      fi

      exec "$VENV/bin/python" server.py --check_update false "$@"
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

      mkdir -p "$DATA"
      cd "$ROOT"

      # Ensure environment exists (but don't upgrade on service start).
      if [ ! -x "$VENV/bin/python" ]; then
        "$UV" venv --python 3.12 "$VENV"
        "$UV" pip install -p "$VENV/bin/python" flask toml pypdf PyMuPDF packaging pdf2zh_next
      fi

      current="$("$VENV/bin/python" - <<'PY'
      try:
          from importlib.metadata import version
          print(version("pdf2zh-next"))
      except Exception:
          print("unknown")
      PY
      )"

      # Refresh only when explicitly updating.
      "$UV" pip install -p "$VENV/bin/python" -U pdf2zh_next

      new="$("$VENV/bin/python" - <<'PY'
      try:
          from importlib.metadata import version
          print(version("pdf2zh-next"))
      except Exception:
          print("unknown")
      PY
      )"

      echo "pdf2zh_next: ${current} -> ${new}"

      # Quick sanity check; don't restart if import fails.
      if ! "$VENV/bin/python" -c "import pdf2zh_next" >/dev/null 2>&1; then
        echo "pdf2zh_next import failed after update; not restarting service."
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
