#!/usr/bin/env python3
"""
Development server that builds, fixes search indices, and serves the documentation.
This replaces `mkdocs serve` to ensure search functionality works correctly.
"""
import os
import sys
import subprocess
import time
import http.server
import socketserver
import threading
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

SITE_DIR = 'site'
POST_BUILD_SCRIPT = 'post_build_fix_search.py'
PORT = 8000

class RebuildHandler(FileSystemEventHandler):
    """Handle file changes and trigger rebuilds"""
    def __init__(self, site_dir, post_build_script):
        self.site_dir = site_dir
        self.post_build_script = post_build_script
        self.last_build = 0
        self.debounce_seconds = 2
        
    def on_any_event(self, event):
        # Ignore changes in site directory and other build artifacts
        if event.src_path.startswith(self.site_dir) or event.src_path.startswith('__pycache__'):
            return
        
        # Ignore non-source files
        if not any(event.src_path.endswith(ext) for ext in ['.md', '.yml', '.html', '.js', '.css', '.py']):
            return
        
        # Debounce rapid changes
        current_time = time.time()
        if current_time - self.last_build < self.debounce_seconds:
            return
        
        self.last_build = current_time
        print(f"\n📝 Change detected: {event.src_path}")
        self.rebuild()
    
    def rebuild(self):
        """Rebuild the documentation and fix search indices"""
        print("🔨 Rebuilding documentation...")
        try:
            # Build
            result = subprocess.run(['mkdocs', 'build'], 
                                  capture_output=True, 
                                  text=True,
                                  timeout=60)
            if result.returncode != 0:
                print(f"❌ Build failed:\n{result.stderr}")
                return
            
            # Fix search indices
            if os.path.exists(self.post_build_script):
                print("🔍 Fixing search indices...")
                fix_result = subprocess.run([sys.executable, self.post_build_script, self.site_dir],
                                          capture_output=True,
                                          text=True,
                                          timeout=10)
                if fix_result.returncode == 0:
                    print("✅ Search indices fixed")
                else:
                    print(f"⚠️  Search fix had issues: {fix_result.stderr}")
            
            print("✅ Rebuild complete!\n")
        except subprocess.TimeoutExpired:
            print("❌ Build timed out")
        except Exception as e:
            print(f"❌ Error during rebuild: {e}")

def serve_site(site_dir, port):
    """Serve the site directory using Python's http.server"""
    os.chdir(site_dir)
    handler = http.server.SimpleHTTPRequestHandler
    
    # Add CORS headers for development
    class CORSRequestHandler(handler):
        def end_headers(self):
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', '*')
            super().end_headers()
    
    with socketserver.TCPServer(("", port), CORSRequestHandler) as httpd:
        print(f"🌐 Serving documentation at http://127.0.0.1:{port}/")
        print("   Press Ctrl+C to stop\n")
        httpd.serve_forever()

def main():
    """Main entry point"""
    # Check if watchdog is available
    try:
        import watchdog
    except ImportError:
        print("⚠️  'watchdog' not installed. Install it for auto-rebuild:")
        print("   pip install watchdog")
        print("\n📦 Building once and serving without auto-rebuild...\n")
        
        # Build once
        subprocess.run(['mkdocs', 'build'], check=True)
        if os.path.exists(POST_BUILD_SCRIPT):
            subprocess.run([sys.executable, POST_BUILD_SCRIPT, SITE_DIR], check=False)
        
        # Serve
        serve_site(SITE_DIR, PORT)
        return
    
    # Initial build
    print("🔨 Initial build...")
    subprocess.run(['mkdocs', 'build'], check=True)
    if os.path.exists(POST_BUILD_SCRIPT):
        print("🔍 Fixing search indices...")
        subprocess.run([sys.executable, POST_BUILD_SCRIPT, SITE_DIR], check=False)
    print("✅ Initial build complete!\n")
    
    # Set up file watcher
    event_handler = RebuildHandler(SITE_DIR, POST_BUILD_SCRIPT)
    observer = Observer()
    
    # Watch docs, custom_theme, and config files
    watch_dirs = ['docs', 'custom_theme', '.']
    for watch_dir in watch_dirs:
        if os.path.exists(watch_dir):
            observer.schedule(event_handler, watch_dir, recursive=True)
            print(f"👀 Watching {watch_dir}/ for changes...")
    
    observer.start()
    
    try:
        # Serve the site
        serve_site(SITE_DIR, PORT)
    except KeyboardInterrupt:
        print("\n\n🛑 Stopping server...")
        observer.stop()
    finally:
        observer.join()

if __name__ == '__main__':
    main()

