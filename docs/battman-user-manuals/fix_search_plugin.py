"""
Fix for search.html not being generated with custom theme (name: null)
Also filters search indices per language to prevent cross-contamination
"""
from mkdocs.plugins import BasePlugin
import os
import shutil
import json
import copy


class FixSearchPlugin(BasePlugin):
    """Ensure search.html is added to static_templates and filter search indices per language"""
    
    def __init__(self):
        super().__init__()
    
    def on_config(self, config, **kwargs):
        # Ensure static_templates exists
        if not hasattr(config.theme, 'static_templates'):
            config.theme.static_templates = set()
        
        # Manually add search.html to static_templates
        config.theme.static_templates.add('search.html')
        
        return config
    
    def _translate_search_html(self, search_html_path, lang_code):
        """Translate search.html content for the specified language"""
        if not os.path.exists(search_html_path):
            return
        
        try:
            with open(search_html_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            if lang_code == 'zh':
                # Replace English text with Chinese using regex for precise matching
                import re
                
                # Update site name in header
                content = re.sub(
                    r'<div class="bm-site-name">\s*Battman User Manual\s*</div>',
                    r'<div class="bm-site-name">Battman 用户手册</div>',
                    content
                )
                # Update h1 tags
                content = re.sub(
                    r'<h1[^>]*>\s*Search Results\s*</h1>',
                    r'<h1>搜索结果</h1>',
                    content
                )
                # Update page title in header
                content = re.sub(
                    r'<div class="bm-page-title">\s*Search Results\s*</div>',
                    r'<div class="bm-page-title">搜索结果</div>',
                    content
                )
                # Update no results message
                content = re.sub(
                    r'<p class="bm-search-no-results">\s*No results found\s*</p>',
                    r'<p class="bm-search-no-results">未找到结果</p>',
                    content
                )
                # Update document title
                content = re.sub(
                    r'<title>\s*Search Results\s*-',
                    r'<title>搜索结果 -',
                    content
                )
                # Update footer copyright
                content = re.sub(
                    r'<span>©\s*Battman User Manual\s*</span>',
                    r'<span>© Battman 用户手册</span>',
                    content
                )
                
                with open(search_html_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                
                print(f"Translated search.html for {lang_code}")
        except Exception as e:
            print(f"Error translating search.html for {lang_code}: {e}")
    
    def _filter_search_index(self, search_index_json, lang_code):
        """Filter a search index file to only include documents for the specified language"""
        if not os.path.exists(search_index_json):
            return
        
        try:
            with open(search_index_json, 'r', encoding='utf-8') as f:
                search_data = json.load(f)
            
            original_count = len(search_data.get('docs', []))
            
            if 'docs' in search_data:
                other_langs = ['zh', 'fr', 'de', 'es', 'ja', 'ko']
                
                if lang_code == 'en':
                    # English: include pages that don't start with any language prefix
                    filtered_docs = [
                        doc for doc in search_data['docs']
                        if not any(doc.get('location', '').startswith(f"{l}/") for l in other_langs)
                    ]
                else:
                    # Other languages: include only pages with this language prefix
                    lang_prefix = f"{lang_code}/"
                    filtered_docs = [
                        doc for doc in search_data['docs']
                        if doc.get('location', '').startswith(lang_prefix)
                    ]
                
                search_data['docs'] = filtered_docs
                filtered_count = len(filtered_docs)
                
                # Remove pre-built index
                if 'index' in search_data:
                    del search_data['index']
                
                # Write filtered index
                temp_file = search_index_json + '.tmp'
                with open(temp_file, 'w', encoding='utf-8') as f:
                    json.dump(search_data, f, ensure_ascii=False, indent=2)
                
                if os.path.exists(temp_file):
                    if os.path.exists(search_index_json):
                        os.remove(search_index_json)
                    os.rename(temp_file, search_index_json)
                
                file_name = os.path.basename(os.path.dirname(search_index_json))
                print(f"Filtered {file_name} index for {lang_code}: {original_count} -> {filtered_count} docs")
        except Exception as e:
            print(f"Error filtering search index {search_index_json}: {e}")
    
    def on_post_build(self, config, **kwargs):
        """After build, filter search indices for each language"""
        site_dir = config['site_dir']
        
        # Skip temp directories (i18n plugin builds to temp first)
        if '/tmp/' in site_dir or '/var/folders/' in site_dir:
            return
        
        search_dir = os.path.join(site_dir, 'search')
        search_html = os.path.join(site_dir, 'search.html')
        root_search_index = os.path.join(search_dir, 'search_index.json')
        
        if not os.path.exists(search_dir) or not os.path.exists(search_html) or not os.path.exists(root_search_index):
            return
        
        # Check for language directories - only process when we have them (final build)
        lang_dirs = [item for item in os.listdir(site_dir) 
                    if os.path.isdir(os.path.join(site_dir, item)) 
                    and item in ['zh', 'fr', 'de', 'es', 'ja', 'ko']
                    and os.path.exists(os.path.join(site_dir, item, 'index.html'))]
        
        if not lang_dirs:
            return  # First build (English only), skip
        
        # Read root index - it should have all languages at this point
        real_root = os.path.realpath(root_search_index)
        with open(real_root, 'r', encoding='utf-8') as f:
            root_index_data = json.load(f)
        root_count = len(root_index_data.get('docs', []))
        
        # If root index doesn't have all languages, something is wrong
        if root_count < 300:
            print(f"WARNING: Root index has {root_count} docs (expected ~384). Search filtering may be incomplete.")
            # Try to continue anyway with what we have
        
        original_index = copy.deepcopy(root_index_data)
        print(f"Processing search indices: root has {root_count} docs, {len(lang_dirs)} language dirs")
        
        # Process each language directory
        for lang_code in lang_dirs:
            lang_dir = os.path.join(site_dir, lang_code)
            
            # Ensure search.html exists and translate it
            lang_search_html = os.path.join(lang_dir, 'search.html')
            if not os.path.exists(lang_search_html):
                shutil.copy2(search_html, lang_search_html)
            
            # Translate search.html for this language
            if os.path.exists(lang_search_html):
                self._translate_search_html(lang_search_html, lang_code)
            
            # Copy stylesheets, javascripts, and images directories if they don't exist
            # These are needed for the search page to load CSS, JS, and images correctly
            stylesheets_dir = os.path.join(site_dir, 'stylesheets')
            javascripts_dir = os.path.join(site_dir, 'javascripts')
            images_dir = os.path.join(site_dir, 'images')
            lang_stylesheets = os.path.join(lang_dir, 'stylesheets')
            lang_javascripts = os.path.join(lang_dir, 'javascripts')
            lang_images = os.path.join(lang_dir, 'images')
            
            if os.path.exists(stylesheets_dir) and not os.path.exists(lang_stylesheets):
                if os.path.islink(lang_stylesheets):
                    os.unlink(lang_stylesheets)
                shutil.copytree(stylesheets_dir, lang_stylesheets)
                print(f"Copied stylesheets to {lang_code}/")
            
            if os.path.exists(javascripts_dir) and not os.path.exists(lang_javascripts):
                if os.path.islink(lang_javascripts):
                    os.unlink(lang_javascripts)
                shutil.copytree(javascripts_dir, lang_javascripts)
                print(f"Copied javascripts to {lang_code}/")
            
            if os.path.exists(images_dir) and not os.path.exists(lang_images):
                if os.path.islink(lang_images):
                    os.unlink(lang_images)
                shutil.copytree(images_dir, lang_images)
                print(f"Copied images to {lang_code}/")
            
            # Handle search directory
            lang_search_dir = os.path.join(lang_dir, 'search')
            if os.path.exists(lang_search_dir) and os.path.islink(lang_search_dir):
                os.unlink(lang_search_dir)
            
            if not os.path.exists(lang_search_dir):
                os.makedirs(lang_search_dir, exist_ok=True)
            
            # Copy all search files
            for search_item in os.listdir(search_dir):
                src = os.path.join(search_dir, search_item)
                dst = os.path.join(lang_search_dir, search_item)
                if os.path.isfile(src):
                    shutil.copy2(src, dst)
                elif os.path.isdir(src) and not os.path.exists(dst):
                    shutil.copytree(src, dst)
            
            # Write original index and filter for this language
            lang_search_index = os.path.join(lang_search_dir, 'search_index.json')
            if os.path.islink(lang_search_index):
                os.unlink(lang_search_index)
            
            lang_index_copy = copy.deepcopy(original_index)
            with open(lang_search_index, 'w', encoding='utf-8') as f:
                json.dump(lang_index_copy, f, ensure_ascii=False, indent=2)
            self._filter_search_index(lang_search_index, lang_code)
        
        # Finally, filter root index for English
        # Always restore original and filter (in case it was modified)
        if root_count > 300:
            root_index_copy = copy.deepcopy(original_index)
            with open(real_root, 'w', encoding='utf-8') as f:
                json.dump(root_index_copy, f, ensure_ascii=False, indent=2)
            self._filter_search_index(real_root, 'en')
        
        print(f"Completed: Root and {len(lang_dirs)} language indices processed")
        
        # Final pass: The i18n plugin may overwrite our changes after we run.
        # Do a final check and fix if needed. We'll also create a marker file
        # that a post-build hook can use, but try to fix it now too.
        import time
        time.sleep(0.5)  # Wait for any file operations to complete
        
        # Re-read root index and fix if needed
        with open(real_root, 'r', encoding='utf-8') as f:
            final_check = json.load(f)
        final_check_count = len(final_check.get('docs', []))
        
        if final_check_count > 300:
            # Still has all languages - filter it
            print(f"Final pass: Filtering root index ({final_check_count} docs)...")
            self._filter_search_index(real_root, 'en')
        
        # Create a marker file indicating we've processed
        # This can be used by external scripts or hooks
        marker_file = os.path.join(site_dir, '.search_indices_filtered')
        with open(marker_file, 'w') as f:
            f.write(f'processed\n')
        
        print(f"✅ Search indices processed: {len(lang_dirs)} language dirs")
