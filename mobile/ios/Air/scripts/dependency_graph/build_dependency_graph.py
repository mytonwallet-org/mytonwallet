#!/usr/bin/env python3
"""
Swift Module Dependency Graph Builder

This script scans the Air/SubModules directory to build a dependency graph
based on import statements in Swift files.
"""

import os
import re
import json
import argparse
from pathlib import Path
from collections import defaultdict, deque
from typing import Dict, Set, List, Tuple


class DependencyGraphBuilder:
    def __init__(self, submodules_path: str):
        self.submodules_path = Path(submodules_path)
        self.modules = {}  # module_name -> module_info
        self.dependencies = defaultdict(set)  # module_name -> set of dependencies
        self.reverse_dependencies = defaultdict(set)  # module_name -> set of dependents
        
    def scan_modules(self) -> None:
        """Scan the SubModules directory to find all modules."""
        if not self.submodules_path.exists():
            raise FileNotFoundError(f"SubModules directory not found: {self.submodules_path}")
        
        for item in self.submodules_path.iterdir():
            if item.is_dir():
                module_name = item.name
                self.modules[module_name] = {
                    'path': item,
                    'swift_files': [],
                    'imports': set()
                }
                
        print(f"Found {len(self.modules)} modules:")
        for module in sorted(self.modules.keys()):
            print(f"  - {module}")
        print()
    
    def find_swift_files(self) -> None:
        """Find all Swift files in each module."""
        for module_name, module_info in self.modules.items():
            swift_files = []
            module_path = module_info['path']
            
            # Recursively find all .swift files
            for swift_file in module_path.rglob('*.swift'):
                swift_files.append(swift_file)
            
            module_info['swift_files'] = swift_files
            print(f"{module_name}: {len(swift_files)} Swift files")
    
    def extract_imports(self) -> None:
        """Extract import statements from all Swift files."""
        import_pattern = re.compile(r'^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)', re.MULTILINE)
        
        for module_name, module_info in self.modules.items():
            all_imports = set()
            
            for swift_file in module_info['swift_files']:
                try:
                    with open(swift_file, 'r', encoding='utf-8') as f:
                        content = f.read()
                        imports = import_pattern.findall(content)
                        all_imports.update(imports)
                except Exception as e:
                    print(f"Warning: Could not read {swift_file}: {e}")
            
            # Filter imports to only include modules that exist in our SubModules
            filtered_imports = all_imports & set(self.modules.keys())
            module_info['imports'] = all_imports
            
            # Build dependency relationships
            self.dependencies[module_name] = filtered_imports
            for dependency in filtered_imports:
                self.reverse_dependencies[dependency].add(module_name)
            
            if filtered_imports:
                print(f"{module_name} depends on: {', '.join(sorted(filtered_imports))}")
    
    def detect_cycles(self) -> List[List[str]]:
        """Detect circular dependencies using DFS."""
        def dfs(node: str, path: List[str], visited: Set[str], rec_stack: Set[str]) -> List[List[str]]:
            if node in rec_stack:
                # Found a cycle, extract it
                cycle_start = path.index(node)
                return [path[cycle_start:] + [node]]
            
            if node in visited:
                return []
            
            visited.add(node)
            rec_stack.add(node)
            path.append(node)
            
            cycles = []
            for dependency in self.dependencies.get(node, []):
                cycles.extend(dfs(dependency, path.copy(), visited, rec_stack.copy()))
            
            rec_stack.remove(node)
            return cycles
        
        all_cycles = []
        visited = set()
        
        for module in self.modules.keys():
            if module not in visited:
                cycles = dfs(module, [], visited, set())
                all_cycles.extend(cycles)
        
        return all_cycles
    
    def topological_sort(self) -> List[str]:
        """Perform topological sort to get build order."""
        in_degree = {module: 0 for module in self.modules.keys()}
        
        # Calculate in-degrees
        for module in self.modules.keys():
            for dependency in self.dependencies[module]:
                in_degree[dependency] += 1
        
        # Find modules with no dependencies
        queue = deque([module for module, degree in in_degree.items() if degree == 0])
        result = []
        
        while queue:
            current = queue.popleft()
            result.append(current)
            
            # Reduce in-degree for dependent modules
            for dependent in self.reverse_dependencies[current]:
                in_degree[dependent] -= 1
                if in_degree[dependent] == 0:
                    queue.append(dependent)
        
        return result
    
    def _categorize_modules(self) -> Dict[str, List[str]]:
        """Categorize modules into logical groups for visualization."""
        categories = {
            'main_app': [],
            'core_foundation': [],
            'ui_features': [],
            'infrastructure': []
        }
        
        # Define the categorization rules
        main_app_modules = {'AirAsFramework', 'UICreateWallet', 'UIHome'}
        core_foundation_modules = {'WalletCore', 'WalletContext', 'UIComponents', 'UICharts', 'UIPasscode', 'Ledger'}
        
        for module in self.modules.keys():
            if module in main_app_modules:
                categories['main_app'].append(module)
            elif module in core_foundation_modules:
                categories['core_foundation'].append(module)
            elif module.startswith('UI'):
                categories['ui_features'].append(module)
            else:
                categories['infrastructure'].append(module)
        
        # Sort modules within each category
        for category in categories.values():
            category.sort()
        
        return categories
    
    def generate_stats(self) -> Dict:
        """Generate dependency statistics."""
        stats = {
            'total_modules': len(self.modules),
            'total_dependencies': sum(len(deps) for deps in self.dependencies.values()),
            'modules_with_dependencies': len([m for m, deps in self.dependencies.items() if deps]),
            'modules_without_dependencies': len([m for m, deps in self.dependencies.items() if not deps]),
            'most_dependent_modules': [],
            'most_depended_on_modules': [],
        }
        
        # Most dependent modules (modules that depend on many others)
        dependent_counts = [(module, len(deps)) for module, deps in self.dependencies.items()]
        dependent_counts.sort(key=lambda x: x[1], reverse=True)
        stats['most_dependent_modules'] = dependent_counts[:5]
        
        # Most depended-on modules (modules that many others depend on)
        depended_counts = [(module, len(deps)) for module, deps in self.reverse_dependencies.items()]
        depended_counts.sort(key=lambda x: x[1], reverse=True)
        stats['most_depended_on_modules'] = depended_counts[:5]
        
        return stats
    
    def export_to_dot(self, output_file: str) -> None:
        """Export dependency graph to DOT format for visualization with clustering."""
        categories = self._categorize_modules()
        
        # Define colors and styles for each category
        category_styles = {
            'main_app': {
                'fillcolor': '#ff6b6b',
                'style': 'filled,bold',
                'label': 'Main Application',
                'color': '#d63031'
            },
            'core_foundation': {
                'fillcolor': '#4ecdc4',
                'style': 'filled,bold',
                'label': 'Core Foundation',
                'color': '#00b894'
            },
            'ui_features': {
                'fillcolor': '#ffe66d',
                'style': 'filled',
                'label': 'UI Features',
                'color': '#fdcb6e'
            },
            'infrastructure': {
                'fillcolor': '#a8e6cf',
                'style': 'filled',
                'label': 'Infrastructure',
                'color': '#00b894'
            }
        }
        
        with open(output_file, 'w') as f:
            f.write("digraph DependencyGraph {\n")
            f.write("  rankdir=TB;\n")
            f.write("  node [shape=box, fontname=\"Helvetica\", fontsize=10];\n")
            f.write("  edge [fontname=\"Helvetica\", fontsize=8];\n")
            f.write("  compound=true;\n")
            f.write("  newrank=true;\n")
            f.write("  splines=true;\n")
            f.write("  overlap=false;\n\n")
            
            # Create subgraphs for each category
            cluster_id = 0
            for category_name, modules in categories.items():
                if not modules:  # Skip empty categories
                    continue
                    
                style = category_styles[category_name]
                f.write(f'  subgraph cluster_{cluster_id} {{\n')
                f.write(f'    label="{style["label"]}";\n')
                f.write(f'    style="filled,rounded";\n')
                f.write(f'    fillcolor="{style["color"]}30";\n')  # Add transparency
                f.write(f'    color="{style["color"]}";\n')
                f.write(f'    fontname="Helvetica-Bold";\n')
                f.write(f'    fontsize=12;\n')
                f.write(f'    penwidth=2;\n\n')
                
                # Add nodes for this category
                for module in modules:
                    f.write(f'    "{module}" [fillcolor="{style["fillcolor"]}", ')
                    f.write(f'style="{style["style"]}", ')
                    f.write(f'color="{style["color"]}"];\n')
                
                f.write("  }\n\n")
                cluster_id += 1
            
            # Add edges
            f.write("  // Dependencies\n")
            for module, dependencies in self.dependencies.items():
                for dependency in dependencies:
                    # Add some styling to edges based on types
                    edge_style = ""
                    if module == dependency:  # Self-reference (circular)
                        edge_style = ' [color=red, style=dashed, penwidth=2, label="circular!"]'
                    elif dependency in ['WalletCore', 'WalletContext', 'UIComponents', 'UICharts', 'UIPasscode', 'Ledger']:
                        edge_style = ' [color=gray, penwidth=1]'  # Dependencies to core modules
                    elif dependency.startswith('UI'):
                        edge_style = ' [color=blue, penwidth=1.5]'  # UI to UI dependencies
                    
                    f.write(f'  "{module}" -> "{dependency}"{edge_style};\n')
            
            f.write("}\n")
        
        print(f"DOT file exported to: {output_file}")
        print("You can visualize it using:")
        print(f"  • PNG: dot -Tpng {output_file} -o dependency_graph.png")
        print(f"  • SVG: dot -Tsvg {output_file} -o dependency_graph.svg")
        print(f"  • PDF: dot -Tpdf {output_file} -o dependency_graph.pdf")
    
    def export_to_json(self, output_file: str) -> None:
        """Export dependency data to JSON format."""
        categories = self._categorize_modules()
        
        data = {
            'modules': {
                name: {
                    'swift_files_count': len(info['swift_files']),
                    'all_imports': sorted(list(info['imports'])),
                    'module_dependencies': sorted(list(self.dependencies[name]))
                }
                for name, info in self.modules.items()
            },
            'dependency_graph': {
                module: sorted(list(deps)) for module, deps in self.dependencies.items()
            },
            'reverse_dependencies': {
                module: sorted(list(deps)) for module, deps in self.reverse_dependencies.items()
            },
            'module_categories': categories
        }
        
        with open(output_file, 'w') as f:
            json.dump(data, f, indent=2)
        
        print(f"JSON data exported to: {output_file}")
    
    def print_report(self) -> None:
        """Print a comprehensive dependency report."""
        print("\n" + "="*60)
        print("DEPENDENCY GRAPH ANALYSIS REPORT")
        print("="*60)
        
        stats = self.generate_stats()
        
        print(f"\nSTATISTICS:")
        print(f"  Total modules: {stats['total_modules']}")
        print(f"  Total dependencies: {stats['total_dependencies']}")
        print(f"  Modules with dependencies: {stats['modules_with_dependencies']}")
        print(f"  Modules without dependencies: {stats['modules_without_dependencies']}")
        
        print(f"\nMOST DEPENDENT MODULES (depend on many others):")
        for module, count in stats['most_dependent_modules']:
            if count > 0:
                print(f"  {module}: {count} dependencies")
        
        print(f"\nMOST DEPENDED-ON MODULES (many others depend on them):")
        for module, count in stats['most_depended_on_modules']:
            if count > 0:
                print(f"  {module}: {count} dependents")
        
        # Check for cycles
        cycles = self.detect_cycles()
        if cycles:
            print(f"\nCIRCULAR DEPENDENCIES DETECTED:")
            for i, cycle in enumerate(cycles, 1):
                print(f"  Cycle {i}: {' -> '.join(cycle)}")
        else:
            print(f"\nNo circular dependencies detected! ✅")
        
        # Topological sort
        try:
            build_order = self.topological_sort()
            if len(build_order) == len(self.modules):
                print(f"\nSUGGESTED BUILD ORDER:")
                for i, module in enumerate(build_order, 1):
                    print(f"  {i:2d}. {module}")
            else:
                print(f"\nCannot determine build order due to circular dependencies.")
        except Exception as e:
            print(f"\nError determining build order: {e}")
        
        # Show module categories
        categories = self._categorize_modules()
        print(f"\nMODULE CATEGORIES:")
        category_names = {
            'main_app': 'Main Application',
            'core_foundation': 'Core Foundation', 
            'ui_features': 'UI Features',
            'infrastructure': 'Infrastructure'
        }
        for category, modules in categories.items():
            if modules:
                print(f"  {category_names[category]}:")
                for module in modules:
                    deps_count = len(self.dependencies[module])
                    dependents_count = len(self.reverse_dependencies[module])
                    print(f"    • {module} ({deps_count} deps, {dependents_count} dependents)")
        
        print(f"\nDETAILED DEPENDENCIES:")
        for module in sorted(self.modules.keys()):
            deps = self.dependencies[module]
            if deps:
                print(f"  {module}:")
                for dep in sorted(deps):
                    print(f"    -> {dep}")
            else:
                print(f"  {module}: (no dependencies)")


def main():
    parser = argparse.ArgumentParser(description='Build Swift module dependency graph')
    parser.add_argument('--submodules-path', default='../SubModules', 
                       help='Path to SubModules directory (default: ../SubModules)')
    parser.add_argument('--output-dot', default='dependency_graph.dot',
                       help='Output DOT file for graph visualization')
    parser.add_argument('--output-json', default='dependency_data.json',
                       help='Output JSON file with dependency data')
    parser.add_argument('--no-exports', action='store_true',
                       help='Skip exporting files, only show report')
    
    args = parser.parse_args()
    
    try:
        builder = DependencyGraphBuilder(args.submodules_path)
        
        print("Scanning modules...")
        builder.scan_modules()
        
        print("Finding Swift files...")
        builder.find_swift_files()
        
        print("Extracting imports...")
        builder.extract_imports()
        
        builder.print_report()
        
        if not args.no_exports:
            builder.export_to_dot(args.output_dot)
            builder.export_to_json(args.output_json)
        
    except Exception as e:
        print(f"Error: {e}")
        return 1
    
    return 0


if __name__ == '__main__':
    exit(main()) 