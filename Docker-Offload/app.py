"""
Docker Offload Demo Application
A Python Flask application that demonstrates the benefits of Docker Offload
"""

from flask import Flask, jsonify, request, render_template_string
import os
import platform
import psutil
import socket
import time
from datetime import datetime

app = Flask(__name__)

# HTML template for the home page
HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Docker Offload Demo</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .container {
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        }
        h1 {
            color: #2d3748;
            border-bottom: 3px solid #667eea;
            padding-bottom: 10px;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .info-card {
            background: #f7fafc;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }
        .info-card h3 {
            margin-top: 0;
            color: #667eea;
        }
        .metric {
            display: flex;
            justify-content: space-between;
            margin: 10px 0;
            padding: 8px;
            background: white;
            border-radius: 4px;
        }
        .label {
            font-weight: bold;
            color: #4a5568;
        }
        .value {
            color: #2d3748;
            font-family: monospace;
        }
        .badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: bold;
            background: #48bb78;
            color: white;
        }
        .endpoints {
            margin-top: 30px;
        }
        .endpoint {
            background: #edf2f7;
            padding: 15px;
            margin: 10px 0;
            border-radius: 6px;
            border-left: 3px solid #667eea;
        }
        .endpoint code {
            background: #2d3748;
            color: #f7fafc;
            padding: 3px 8px;
            border-radius: 3px;
            font-size: 14px;
        }
        .footer {
            margin-top: 30px;
            text-align: center;
            color: #718096;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🐳 Docker Offload Demo <span class="badge">RUNNING IN CLOUD</span></h1>
        
        <p style="font-size: 18px; color: #4a5568;">
            This application is running via <strong>Docker Offload</strong> - 
            built and executed in the cloud while you control it from Docker Desktop locally!
        </p>
        
        <div class="info-grid">
            <div class="info-card">
                <h3>🖥️ System Information</h3>
                <div class="metric">
                    <span class="label">Hostname:</span>
                    <span class="value">{{ hostname }}</span>
                </div>
                <div class="metric">
                    <span class="label">Platform:</span>
                    <span class="value">{{ platform }}</span>
                </div>
                <div class="metric">
                    <span class="label">Python:</span>
                    <span class="value">{{ python_version }}</span>
                </div>
                <div class="metric">
                    <span class="label">IP Address:</span>
                    <span class="value">{{ ip_address }}</span>
                </div>
            </div>
            
            <div class="info-card">
                <h3>⚡ Resource Usage</h3>
                <div class="metric">
                    <span class="label">CPU Usage:</span>
                    <span class="value">{{ cpu_percent }}%</span>
                </div>
                <div class="metric">
                    <span class="label">Memory Total:</span>
                    <span class="value">{{ memory_total }} GB</span>
                </div>
                <div class="metric">
                    <span class="label">Memory Used:</span>
                    <span class="value">{{ memory_used }}%</span>
                </div>
                <div class="metric">
                    <span class="label">CPU Cores:</span>
                    <span class="value">{{ cpu_count }}</span>
                </div>
            </div>
            
            <div class="info-card">
                <h3>🌐 Environment</h3>
                <div class="metric">
                    <span class="label">Deployment:</span>
                    <span class="value">{{ deployment }}</span>
                </div>
                <div class="metric">
                    <span class="label">Started:</span>
                    <span class="value">{{ start_time }}</span>
                </div>
                <div class="metric">
                    <span class="label">Uptime:</span>
                    <span class="value">{{ uptime }} seconds</span>
                </div>
                <div class="metric">
                    <span class="label">Status:</span>
                    <span class="value">✅ Healthy</span>
                </div>
            </div>
        </div>
        
        <div class="endpoints">
            <h2>📡 Available API Endpoints</h2>
            <div class="endpoint">
                <code>GET /</code> - This home page with system information
            </div>
            <div class="endpoint">
                <code>GET /health</code> - Health check endpoint
            </div>
            <div class="endpoint">
                <code>GET /api/info</code> - Detailed JSON system information
            </div>
            <div class="endpoint">
                <code>POST /api/process</code> - CPU-intensive task simulation
            </div>
            <div class="endpoint">
                <code>GET /api/build-info</code> - Docker build information
            </div>
        </div>
        
        <div class="footer">
            <p>Built with ❤️ using Docker Offload | Running in the Cloud ☁️</p>
            <p>Current Time: {{ current_time }}</p>
        </div>
    </div>
</body>
</html>
"""

# Store application start time
start_time = datetime.now()

@app.route('/')
def home():
    """Home page with system information"""
    try:
        memory = psutil.virtual_memory()
        uptime = (datetime.now() - start_time).total_seconds()
        
        return render_template_string(
            HTML_TEMPLATE,
            hostname=socket.gethostname(),
            platform=platform.platform(),
            python_version=platform.python_version(),
            ip_address=socket.gethostbyname(socket.gethostname()),
            cpu_percent=round(psutil.cpu_percent(interval=1), 2),
            memory_total=round(memory.total / (1024**3), 2),
            memory_used=round(memory.percent, 2),
            cpu_count=psutil.cpu_count(),
            deployment=os.getenv('DEPLOYMENT_TYPE', 'Docker Offload'),
            start_time=start_time.strftime('%Y-%m-%d %H:%M:%S'),
            uptime=round(uptime, 0),
            current_time=datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        )
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'deployment': os.getenv('DEPLOYMENT_TYPE', 'Docker Offload')
    }), 200

@app.route('/api/info')
def api_info():
    """Detailed system information in JSON format"""
    try:
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        uptime = (datetime.now() - start_time).total_seconds()
        
        return jsonify({
            'system': {
                'hostname': socket.gethostname(),
                'platform': platform.platform(),
                'processor': platform.processor(),
                'architecture': platform.machine(),
                'python_version': platform.python_version()
            },
            'resources': {
                'cpu': {
                    'count': psutil.cpu_count(),
                    'usage_percent': round(psutil.cpu_percent(interval=1), 2)
                },
                'memory': {
                    'total_gb': round(memory.total / (1024**3), 2),
                    'available_gb': round(memory.available / (1024**3), 2),
                    'used_percent': round(memory.percent, 2)
                },
                'disk': {
                    'total_gb': round(disk.total / (1024**3), 2),
                    'used_gb': round(disk.used / (1024**3), 2),
                    'free_gb': round(disk.free / (1024**3), 2),
                    'used_percent': round(disk.percent, 2)
                }
            },
            'application': {
                'deployment_type': os.getenv('DEPLOYMENT_TYPE', 'Docker Offload'),
                'start_time': start_time.isoformat(),
                'uptime_seconds': round(uptime, 2),
                'port': os.getenv('PORT', '8080')
            },
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/process', methods=['POST'])
def process_data():
    """Simulate a CPU-intensive task"""
    try:
        data = request.get_json() or {}
        iterations = min(data.get('iterations', 1000000), 10000000)  # Cap at 10M
        
        start = time.time()
        
        # Simulate CPU-intensive work
        result = 0
        for i in range(iterations):
            result += i ** 2 % 1000
        
        duration = time.time() - start
        
        return jsonify({
            'status': 'completed',
            'iterations': iterations,
            'result': result,
            'duration_seconds': round(duration, 4),
            'ops_per_second': round(iterations / duration, 2),
            'message': f'Processed {iterations:,} iterations in the cloud',
            'deployment': os.getenv('DEPLOYMENT_TYPE', 'Docker Offload'),
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 400

@app.route('/api/build-info')
def build_info():
    """Information about the Docker build"""
    return jsonify({
        'build': {
            'method': 'Docker Offload',
            'description': 'Built in the cloud using Docker managed infrastructure',
            'benefits': [
                'Faster builds with cloud resources',
                'No local compute overhead',
                'Consistent build environment',
                'Works on VDI and low-powered machines'
            ]
        },
        'environment': {
            'DEPLOYMENT_TYPE': os.getenv('DEPLOYMENT_TYPE', 'Docker Offload'),
            'BUILD_DATE': os.getenv('BUILD_DATE', 'N/A'),
            'VERSION': os.getenv('VERSION', '1.0.0')
        },
        'timestamp': datetime.now().isoformat()
    })

if __name__ == '__main__':
    port = int(os.getenv('PORT', 8080))
    print(f"🚀 Starting Docker Offload Demo App on port {port}")
    print(f"📊 Running in: {os.getenv('DEPLOYMENT_TYPE', 'Docker Offload')}")
    app.run(host='0.0.0.0', port=port, debug=False)
