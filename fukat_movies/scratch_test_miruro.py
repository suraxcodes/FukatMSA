import urllib.request
import json
import urllib.error

try:
    # 1. Get Anilist ID
    req = urllib.request.Request('https://graphql.anilist.co', 
        headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'}, 
        data=json.dumps({
            'query': 'query { Media(search: "Naruto", type: ANIME, sort: SEARCH_MATCH) { id } }'
        }).encode('utf-8'))
    res = urllib.request.urlopen(req)
    anilist_id = json.loads(res.read())['data']['Media']['id']
    print('Anilist ID:', anilist_id)

    # 2. Get Episode List
    ep_url = f'https://miruro-apimsa.onrender.com/episodes/{anilist_id}'
    ep_req = urllib.request.Request(ep_url, headers={'Referer': 'https://fukatmovies.com'})
    ep_res = urllib.request.urlopen(ep_req)
    data = json.loads(ep_res.read())
    
    target_watch_id = None
    for prov, prov_data in data.get('providers', {}).items():
        eps = prov_data.get('episodes', {}).get('sub', [])
        for e in eps:
            if str(e.get('number')) == '1':
                target_watch_id = e.get('id')
                print(f'Provider {prov} has episode 1: {target_watch_id}')
                break
        if target_watch_id:
            break
            
    if not target_watch_id:
        print('Episode 1 not found')
    else:
        # 3. Get Stream
        stream_url = f'https://miruro-apimsa.onrender.com/{target_watch_id}'
        stream_req = urllib.request.Request(stream_url, headers={'Referer': 'https://fukatmovies.com'})
        stream_res = urllib.request.urlopen(stream_req)
        stream_data = json.loads(stream_res.read())
        print('Streams found:', len(stream_data.get('streams', [])))
        for s in stream_data.get('streams', []):
            print('-', s.get('quality'), s.get('type'), s.get('url'))

except urllib.error.HTTPError as e:
    print('HTTP Error:', e.code, e.read().decode())
except Exception as e:
    print('Error:', e)
