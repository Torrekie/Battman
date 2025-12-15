"""
Fix for search.html not being generated with custom theme (name: null)
"""
from mkdocs.plugins import BasePlugin


class FixSearchPlugin(BasePlugin):
    """Ensure search.html is added to static_templates when using name: null theme"""
    
    def on_config(self, config, **kwargs):
        # Ensure static_templates exists
        if not hasattr(config.theme, 'static_templates'):
            config.theme.static_templates = set()
        
        # Manually add search.html to static_templates
        # The search plugin should do this, but with name: null it doesn't
        config.theme.static_templates.add('search.html')
        
        return config

