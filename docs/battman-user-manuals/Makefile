.PHONY: help build serve clean install check fix-search all deploy

# Variables
PYTHON := python3
MKDOCS := mkdocs
SITE_DIR := site
POST_BUILD_SCRIPT := post_build_fix_search.py
PLUGIN_DIR := mkdocs_plugins

# Default target
help:
	@echo "Battman User Manual - Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make build        - Build the documentation"
	@echo "  make serve        - Build, fix search, and serve locally (http://127.0.0.1:8000)"
	@echo "  make clean        - Remove the build directory"
	@echo "  make install      - Install/upgrade the custom plugin"
	@echo "  make check        - Check for common issues"
	@echo "  make fix-search   - Fix search indices after build"
	@echo "  make all          - Clean, build, and fix search indices"
	@echo "  make deploy       - Build, fix search, and deploy to GitHub Pages"
	@echo ""

# Build the documentation
build:
	@echo "Building documentation..."
	$(MKDOCS) build
	@echo "Build complete!"

# Fix search indices after build
fix-search:
	@echo "Fixing search indices..."
	@if [ -f "$(POST_BUILD_SCRIPT)" ]; then \
		$(PYTHON) $(POST_BUILD_SCRIPT) $(SITE_DIR); \
	else \
		echo "Warning: $(POST_BUILD_SCRIPT) not found"; \
	fi

# Build and fix search indices
all: clean build fix-search
	@echo ""
	@echo "✅ Documentation built and search indices fixed!"
	@echo "   Site directory: $(SITE_DIR)/"

# Serve the documentation locally with working search
serve:
	@echo "Starting development server with search fix..."
	@echo "Open http://127.0.0.1:8000 in your browser"
	@if [ -f "serve.sh" ]; then \
		./serve.sh 8000; \
	elif [ -f "dev_server.py" ]; then \
		$(PYTHON) dev_server.py; \
	else \
		echo "⚠️  Using fallback method"; \
		$(MKDOCS) build && $(PYTHON) $(POST_BUILD_SCRIPT) $(SITE_DIR) && cd $(SITE_DIR) && $(PYTHON) -m http.server 8000; \
	fi

# Clean the build directory
clean:
	@echo "Cleaning build directory..."
	@rm -rf $(SITE_DIR)
	@rm -f .fix_search_processed
	@echo "Clean complete!"

# Install/upgrade the custom plugin
install:
	@echo "Installing/upgrading custom plugin..."
	@if [ -f "setup.py" ]; then \
		$(PYTHON) -m pip install -e . --upgrade; \
	else \
		echo "Warning: setup.py not found"; \
	fi

# Check for common issues
check:
	@echo "Checking documentation..."
	@echo ""
	@echo "Checking for required files..."
	@test -f mkdocs.yml || (echo "❌ mkdocs.yml not found" && exit 1)
	@test -f $(POST_BUILD_SCRIPT) || (echo "⚠️  $(POST_BUILD_SCRIPT) not found" && exit 1)
	@test -f fix_search_plugin.py || (echo "⚠️  fix_search_plugin.py not found" && exit 1)
	@echo "✅ Required files present"
	@echo ""
	@echo "Checking Python dependencies..."
	@$(PYTHON) -c "import mkdocs" 2>/dev/null || (echo "❌ mkdocs not installed. Run: pip install mkdocs" && exit 1)
	@$(PYTHON) -c "import mkdocs_static_i18n" 2>/dev/null || (echo "❌ mkdocs-static-i18n not installed. Run: pip install mkdocs-static-i18n" && exit 1)
	@echo "✅ Python dependencies installed"
	@echo ""
	@echo "Checking plugin installation..."
	@$(PYTHON) -c "from fix_search_plugin import FixSearchPlugin" 2>/dev/null || (echo "⚠️  Plugin not installed. Run: make install" && exit 1)
	@echo "✅ Plugin installed"
	@echo ""
	@echo "All checks passed!"

# Verify search indices after build
verify-search:
	@echo "Verifying search indices..."
	@if [ -f "$(SITE_DIR)/search/search_index.json" ]; then \
		$(PYTHON) -c "import json; r=json.load(open('$(SITE_DIR)/search/search_index.json')); print(f'Root index: {len(r.get(\"docs\", []))} docs')"; \
	else \
		echo "❌ Root search index not found"; \
	fi
	@if [ -f "$(SITE_DIR)/zh/search/search_index.json" ]; then \
		$(PYTHON) -c "import json; z=json.load(open('$(SITE_DIR)/zh/search/search_index.json')); print(f'Chinese index: {len(z.get(\"docs\", []))} docs')"; \
	else \
		echo "⚠️  Chinese search index not found"; \
	fi

# Deploy to GitHub Pages
deploy:
	@echo "Deploying to GitHub Pages..."
	@if [ -f "deploy.sh" ]; then \
		./deploy.sh; \
	else \
		echo "❌ deploy.sh not found"; \
		exit 1; \
	fi

