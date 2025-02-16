from flask import Flask, jsonify, request, g, render_template
import sqlite3
import datetime
from pinger import logger

app = Flask(__name__)

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
    if time_range == '24h':
        start = now - datetime.timedelta(hours=24)
    elif time_range == '7d':
        start = now - datetime.timedelta(days=7)
    elif time_range == '30d':
        start = now - datetime.timedelta(days=30)
    elif time_range == 'custom' and start_time and end_time:
        start = datetime.datetime.fromisoformat(start_time)
        end = datetime.datetime.fromisoformat(end_time)
    else:
        return jsonify({'error': 'Invalid time range'}), 400

    # Build query
    query = """
        SELECT 
            strftime('%Y-%m-%d %H:%M', timestamp) as time_bucket,
            country,
            ROUND(AVG(avg_time), 2) as avg_latency
        FROM ping_results
        WHERE timestamp BETWEEN ? AND ?
    """
    params = [start.isoformat(), end.isoformat()]

    if countries:
        query += " AND country IN ({})".format(','.join(['?']*len(countries)))
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

if __name__ == '__main__':
    app.run(debug=True)