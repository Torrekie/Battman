#!/usr/bin/env python3
"""
Post-build script to fix search indices after mkdocs build completes.
This runs after all i18n plugin builds are complete.
"""
import os
import json
import sys

def filter_search_index(search_index_json, lang_code):
    """Filter a search index file to only include documents for the specified language"""
    if not os.path.exists(search_index_json):
        return False
    
    try:
        with open(search_index_json, 'r', encoding='utf-8') as f:
            search_data = json.load(f)
        
        original_count = len(search_data.get('docs', []))
        
        if 'docs' in search_data:
            other_langs = ['zh', 'fr', 'de', 'es', 'ja', 'ko']
            
            if lang_code == 'en':
                filtered_docs = [
                    doc for doc in search_data['docs']
                    if not any(doc.get('location', '').startswith(f"{l}/") for l in other_langs)
                ]
            else:
                lang_prefix = f"{lang_code}/"
                filtered_docs = [
                    doc for doc in search_data['docs']
                    if doc.get('location', '').startswith(lang_prefix)
                ]
            
            search_data['docs'] = filtered_docs
            filtered_count = len(filtered_docs)
            
            if 'index' in search_data:
                del search_data['index']
            
            with open(search_index_json, 'w', encoding='utf-8') as f:
                json.dump(search_data, f, ensure_ascii=False, indent=2)
            
            print(f"Filtered {os.path.basename(os.path.dirname(search_index_json))} index for {lang_code}: {original_count} -> {filtered_count} docs")
            return True
    except Exception as e:
        print(f"Error filtering {search_index_json}: {e}", file=sys.stderr)
        return False
    
    return False

def translate_search_html(search_html_path, lang_code):
    """Translate search.html content for the specified language"""
    if not os.path.exists(search_html_path):
        return False
    
    try:
        with open(search_html_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        if lang_code == 'zh':
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
            
            return True
    except Exception as e:
        print(f"Error translating search.html for {lang_code}: {e}", file=sys.stderr)
        return False
    
    return False

def main():
    site_dir = 'site'
    if len(sys.argv) > 1:
        site_dir = sys.argv[1]
    
    search_dir = os.path.join(site_dir, 'search')
    root_search_index = os.path.join(search_dir, 'search_index.json')
    
    if not os.path.exists(root_search_index):
        print(f"Error: {root_search_index} not found")
        return 1
    
    # Filter root index for English
    print("Filtering root search index for English...")
    filter_search_index(root_search_index, 'en')
    
    # Filter language-specific indices and translate search.html
    for item in os.listdir(site_dir):
        lang_dir = os.path.join(site_dir, item)
        if not os.path.isdir(lang_dir) or item not in ['zh', 'fr', 'de', 'es', 'ja', 'ko']:
            continue
        
        lang_search_index = os.path.join(lang_dir, 'search', 'search_index.json')
        if os.path.exists(lang_search_index):
            print(f"Filtering {item} search index...")
            filter_search_index(lang_search_index, item)
        
        # Translate search.html for this language
        lang_search_html = os.path.join(lang_dir, 'search.html')
        if os.path.exists(lang_search_html):
            if translate_search_html(lang_search_html, item):
                print(f"Translated search.html for {item}")
        
        # Copy images directory if it doesn't exist (needed for logo icon)
        images_dir = os.path.join(site_dir, 'images')
        lang_images = os.path.join(lang_dir, 'images')
        if os.path.exists(images_dir) and not os.path.exists(lang_images):
            import shutil
            shutil.copytree(images_dir, lang_images)
            print(f"Copied images to {item}/")
    
    print("Done!")
    return 0

if __name__ == '__main__':
    sys.exit(main())

