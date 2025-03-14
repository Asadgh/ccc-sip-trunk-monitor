from flask import Flask, jsonify, request, g, render_template, Response
import sqlite3
import datetime
import ast
from pinger import Logger

app = Flask(__name__)
logger = Logger()

DATABASE = 'database.db'

def get_db():
    db = getattr(g, '_database', None)
    if db is None:
        db = g._database = sqlite3.connect(DATABASE)
        db.row_factory = sqlite3.Row
    return db

@app.teardown_appcontext
def close_connection(exception):
    db = getattr(g, '_database', None)
    if db is not None:
        db.close()

def query_db(query, args=(), one=False):
    cur = get_db().execute(query, args)
    rv = cur.fetchall()
    cur.close()
    return (rv[0] if rv else None) if one else rv

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/ping-data', methods=['GET'])
def get_ping_data():
    # Get query parameters
    countries = request.args.getlist('country')
    time_range = request.args.get('range', '24h')
    start_time = request.args.get('start')
    end_time = request.args.get('end')

    # Calculate time ranges
    now = datetime.datetime.now()
    end = now
    if time_range == '1h':
        start = now - datetime.timedelta(hours=1)
    elif time_range == '12h':
        start = now - datetime.timedelta(hours=12)
    elif time_range == '24h':
        start = now - datetime.timedelta(hours=24)
    elif time_range == '7d':
        start = now - datetime.timedelta(days=7)
    elif time_range == '30d':
        start = now - datetime.timedelta(days=30)
    elif time_range == 'custom' and start_time and end_time:
        try:
            start = datetime.datetime.fromisoformat(start_time)
            end = datetime.datetime.fromisoformat(end_time)
        except Exception as e:
            return jsonify({'error': 'Invalid date format'}), 400
    else:
        return jsonify({'error': 'Invalid time range'}), 400

    # Use the same datetime format as stored in the database
    start_str = start.strftime("%Y-%m-%d %H:%M:%S")
    end_str = end.strftime("%Y-%m-%d %H:%M:%S")

    # Build query
    query = """
        SELECT 
            strftime('%Y-%m-%d %H:%M', timestamp) as time_bucket,
            country,
            ROUND(AVG(avg_time), 2) as avg_latency
        FROM ping_results
        WHERE timestamp BETWEEN ? AND ?
    """
    params = [start_str, end_str]

    if countries:
        query += " AND country IN ({})".format(','.join(['?'] * len(countries)))
        params.extend(countries)

    query += " GROUP BY time_bucket, country ORDER BY time_bucket"

    results = query_db(query, params)
    
    # Process results into chart format
    chart_data = {}
    for row in results:
        country = row['country']
        if country not in chart_data:
            chart_data[country] = {
                'timestamps': [],
                'latency': []
            }
        
        chart_data[country]['timestamps'].append(row['time_bucket'])
        chart_data[country]['latency'].append(row['avg_latency'])

    return jsonify(chart_data)

@app.route('/api/get-server-ping-data', methods=['GET'])
def get_server_ping_data():
    # Get query parameters
    country = request.args.get('country')
    time_range = request.args.get('range', '24h')
    start_time = request.args.get('start')
    end_time = request.args.get('end')

    # Calculate time ranges
    now = datetime.datetime.now()
    end = now
    if time_range == '1h':
        start = now - datetime.timedelta(hours=1)
    elif time_range == '12h':
        start = now - datetime.timedelta(hours=12)
    elif time_range == '24h':
        start = now - datetime.timedelta(hours=24)
    elif time_range == '7d':
        start = now - datetime.timedelta(days=7)
    elif time_range == '30d':
        start = now - datetime.timedelta(days=30)
    elif time_range == 'custom' and start_time and end_time:
        try:
            start = datetime.datetime.fromisoformat(start_time)
            end = datetime.datetime.fromisoformat(end_time)
        except Exception as e:
            return jsonify({'error': 'Invalid date format'}), 400
    else:
        return jsonify({'error': 'Invalid time range'}), 400

    # Use the same datetime format as stored in the database
    start_str = start.strftime("%Y-%m-%d %H:%M:%S")
    end_str = end.strftime("%Y-%m-%d %H:%M:%S")

    # Build query
    detailed_data = query_db("""
        SELECT * FROM ping_results
        WHERE country = ?
        AND timestamp BETWEEN ? AND ?
        ORDER BY timestamp DESC
    """, [country, start_str, end_str])

    return jsonify([dict(data) for data in detailed_data])

@app.route('/api/logs', methods=['GET'])
def get_logs():
    limit = request.args.get('limit', default=10, type=int)
    level = request.args.get('level', default='INFO')
    
    logs = query_db("""
        SELECT timestamp, level, message, module 
        FROM logs 
        WHERE level NOT LIKE ?
        ORDER BY timestamp DESC
        LIMIT ?
    """, [level, limit])
    
    return jsonify([dict(log) for log in logs])

@app.route('/api/server/info/<country>', methods=['GET'])
def get_server_info(country):
    server = query_db(f"""
        SELECT 
            country,
            partner,
            dn_ext,
            avg_time,
            success,
            is_high_latency,
            timestamp,
            concerns
        FROM ping_results
        WHERE country = "{country}"
        ORDER BY timestamp DESC
        LIMIT 1
    """, one=True)
    
    status_data: dict;
    now = datetime.datetime.now()

    status_data = {
        'country': country,
        'partner': None,
        'dn_ext': None,
        'latency': None,
        'status': 'Inactive',
        'lastCheck': None,
        'is_high_latency': None,
        'exceptions': None,
        'stale': True
    }

    if server:
        last_check_time = datetime.datetime.fromisoformat(server['timestamp'])
        time_diff = now - last_check_time

        concerns = []

        if time_diff.total_seconds() >= 300:
            concerns.append({'name':'Realtime Data stream lost','detail': f'{server["country"]}'})
            concerns.append({'name': 'Data Stale', 'detail': f'{ round(time_diff.total_seconds() / 60)} minutes Since Last Data Record'})
            logger.log(f'Realtime Data stream lost for {server["country"]}', "WARNING", "SERVER")
            status_data['exceptions'] = concerns
            status_data['timestamp'] = server['timestamp']
            return jsonify(status_data)
        
        concerns_raw = ast.literal_eval(server['concerns'])
        if concerns_raw:
            for concern in concerns_raw:
                info = {}
                conern_info = concern.split(':')
                concern_name = conern_info[0].strip()
                concern_detail = conern_info[-1].strip()

                info['name'] = concern_name
                info['detail'] = concern_detail
                concerns.append(info)

        status_data = {
            'country': server['country'],
            'partner': server['partner'],
            'dn_ext': server['dn_ext'],
            'latency': server['avg_time'],
            'status': 'Active' if server['success'] else 'Inactive',
            'lastCheck': server['timestamp'],
            'is_high_latency': True if server['is_high_latency'] == '1' else False,
            'exceptions': concerns,
            'stale': time_diff.total_seconds() >= 300
        }

    return jsonify(status_data)

@app.route('/api/servers/status', methods=['GET'])
def get_server_status():
    # Get latest status for all servers
    servers = query_db("""
        SELECT 
            country,
            partner,
            avg_time,
            success,
            is_high_latency,
            MAX(timestamp) as last_check
        FROM ping_results
        GROUP BY country
    """)
    
    status_data = []
    stale_data_count = 0
    now = datetime.datetime.now()

    for server in servers:
        last_check_time = datetime.datetime.fromisoformat(server['last_check'])
        time_diff = now - last_check_time

        if time_diff.total_seconds() >= 300:
            logger.log(f'Realtime Data stream lost for {server["country"]}', "WARNING", "SERVER")
            stale_data_count += 1
        
        status_data.append({
            'country': server['country'],
            'partner': server['partner'],
            'latency': server['avg_time'],
            'status': 'Active' if server['success'] else 'Inactive',
            'lastCheck': server['last_check'],
            'warning': server['is_high_latency'],
            'stale': time_diff.total_seconds() >= 300
        })
    
    if len(status_data) == stale_data_count:
        logger.log('Realtime Data stream lost for all servers', "ERROR", "SERVER")
        return jsonify({'error': 'Realtime Data stream lost'}), 400

    return jsonify(status_data)

@app.route('/server/<country>')
def server_details(country):
    detailed_data = query_db("""
        SELECT * FROM ping_results
        WHERE country = ?
        ORDER BY timestamp DESC
        LIMIT 50
    """, [country])
    # Convert sqlite3.Row objects to dictionaries
    detailed_data = [dict(row) for row in detailed_data]
    return render_template('server.html', country=country, data=detailed_data)

@app.route('/api/export-data', methods=['GET'])
def export_data():
    """
    This endpoint returns all columns from the ping_results table as raw data.
    It supports filtering by time range and country.
    The 'format' query parameter specifies CSV (default) or JSON.
    """
    export_format = request.args.get('format', 'csv')
    countries = request.args.getlist('country')
    time_range = request.args.get('range', '24h')
    start_time = request.args.get('start')
    end_time = request.args.get('end')
    
    now = datetime.datetime.now()
    if time_range == '1h':
        start = now - datetime.timedelta(hours=1)
        end = now
    elif time_range == '12h':
        start = now - datetime.timedelta(hours=12)
        end = now
    elif time_range == '24h':
        start = now - datetime.timedelta(hours=24)
        end = now
    elif time_range == '7d':
        start = now - datetime.timedelta(days=7)
        end = now
    elif time_range == '30d':
        start = now - datetime.timedelta(days=30)
        end = now
    elif time_range == 'custom' and start_time and end_time:
        try:
            start = datetime.datetime.fromisoformat(start_time)
            end = datetime.datetime.fromisoformat(end_time)
        except Exception as e:
            return jsonify({'error': 'Invalid date format'}), 400
    else:
        return jsonify({'error': 'Invalid time range'}), 400

    start_str = start.strftime("%Y-%m-%d %H:%M:%S")
    end_str = end.strftime("%Y-%m-%d %H:%M:%S")
    
    query = "SELECT * FROM ping_results WHERE timestamp BETWEEN ? AND ?"
    params = [start_str, end_str]
    
    if countries:
        query += " AND country IN ({})".format(','.join(['?'] * len(countries)))
        params.extend(countries)
    
    query += " ORDER BY timestamp ASC"
    results = query_db(query, params)
    data = [dict(row) for row in results]
    
    if export_format.lower() == 'csv':
        from io import StringIO
        import csv
        si = StringIO()
        if data:
            fieldnames = data[0].keys()
            writer = csv.DictWriter(si, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(data)
        else:
            si.write("No data available")
        output = si.getvalue()
        response = Response(output, mimetype='text/csv')
        response.headers.set("Content-Disposition", "attachment", filename="export_data.csv")
        return response
    else:
        response = jsonify(data)
        response.headers.set("Content-Disposition", "attachment", filename="export_data.json")
        return response


if __name__ == '__main__':
    app.run(debug=True)