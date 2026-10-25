def test_contact_lifecycle_and_tier_sorting(client, authenticated_user):
    headers = authenticated_user['headers']

    # 1. Create Tier 2 Secondary Contact
    res_tier2 = client.post('/api/v1/contacts', headers=headers, json={
        "name": "Doctor Green",
        "phone": "+12025550222",
        "relationship": "Physician",
        "priority_tier": 2
    })
    assert res_tier2.status_code == 201
    c2_id = res_tier2.get_json()['data']['contact']['id']

    # 2. Create Tier 1 Primary Contact
    res_tier1 = client.post('/api/v1/contacts', headers=headers, json={
        "name": "Spouse Sarah",
        "phone": "+12025550111",
        "relationship": "Spouse",
        "priority_tier": 1
    })
    assert res_tier1.status_code == 201

    # 3. List contacts: should return Tier 1 first, then Tier 2
    list_res = client.get('/api/v1/contacts', headers=headers)
    assert list_res.status_code == 200
    contacts = list_res.get_json()['data']['contacts']
    assert len(contacts) == 2
    assert contacts[0]['name'] == "Spouse Sarah"
    assert contacts[0]['priority_tier'] == 1
    assert contacts[1]['name'] == "Doctor Green"
    assert contacts[1]['priority_tier'] == 2

    # 4. Update contact
    put_res = client.put(f'/api/v1/contacts/{c2_id}', headers=headers, json={
        "name": "Dr. Sarah Green",
        "priority_tier": 3
    })
    assert put_res.status_code == 200
    assert put_res.get_json()['data']['contact']['name'] == "Dr. Sarah Green"
    assert put_res.get_json()['data']['contact']['priority_tier'] == 3

    # 5. Delete contact
    del_res = client.delete(f'/api/v1/contacts/{c2_id}', headers=headers)
    assert del_res.status_code == 200
    
    # Verify deletion
    list_after = client.get('/api/v1/contacts', headers=headers)
    assert len(list_after.get_json()['data']['contacts']) == 1


def test_contact_tenant_isolation(client, authenticated_user):
    headers_user1 = authenticated_user['headers']

    # Register User 2
    res_u2 = client.post('/api/v1/auth/register', json={
        "full_name": "User Two",
        "email": "user2@test.com",
        "phone": "+12025550999",
        "password": "Password123!"
    })
    token_u2 = res_u2.get_json()['data']['tokens']['access_token']
    headers_user2 = {"Authorization": f"Bearer {token_u2}"}

    # User 1 creates a contact
    res_c1 = client.post('/api/v1/contacts', headers=headers_user1, json={
        "name": "User1 Guardian",
        "phone": "+12025550001",
        "priority_tier": 1
    })
    contact_id = res_c1.get_json()['data']['contact']['id']

    # User 2 attempts to get or delete User 1's contact -> Should be 404
    assert client.get(f'/api/v1/contacts/{contact_id}', headers=headers_user2).status_code == 404
    assert client.delete(f'/api/v1/contacts/{contact_id}', headers=headers_user2).status_code == 404
