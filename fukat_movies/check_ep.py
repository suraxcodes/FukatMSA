import urllib.request
import json

try:
    req = urllib.request.Request('https://graphql.anilist.co', 
        headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'}, 
        data=json.dumps({
            'query': 'query { Media(search: "One Piece", type: ANIME, sort: SEARCH_MATCH) { id } }'
        }).encode('utf-8'))
    res = urllib.request.urlopen(req)
    anilist_id = json.loads(res.read())['data']['Media']['id']
    print('Anilist ID:', anilist_id)

    ep_url = f'https://miruro-apimsa.onrender.com/episodes/{anilist_id}'
    ep_req = urllib.request.Request(ep_url, headers={'Referer': 'https://fukatmovies.com'})
    ep_res = urllib.request.urlopen(ep_req)
    data = json.loads(ep_res.read())
    found = False
    for prov, prov_data in data.get('providers', {}).items():
        eps = prov_data.get('episodes', {}).get('sub', [])
        for e in eps:
            if str(e.get('number')) == '1165':
                print(f'Provider {prov} has episode 1165 (sub)!')
                found = True
                break
    if not found:
        print('Episode 1165 not found in sub for any provider.')
except Exception as e:
    print('Error:', e)
