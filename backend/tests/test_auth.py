def test_registration_and_login_flow(client):
    # 1. Register new user
    reg_payload = {
        "full_name": "Marcus Aurelius",
        "email": "marcus@rome.org",
        "phone": "+14155550100",
        "password": "Meditations2026!",
        "blood_group": "AB+",
        "default_emergency_number": "112"
    }
    res = client.post('/api/v1/auth/register', json=reg_payload)
    assert res.status_code == 201
    json_data = res.get_json()
    assert json_data['success'] is True
    assert json_data['data']['user']['email'] == "marcus@rome.org"
    assert "access_token" in json_data['data']['tokens']

    # 2. Duplicate registration attempt
    res_dup = client.post('/api/v1/auth/register', json=reg_payload)
    assert res_dup.status_code == 409
    assert res_dup.get_json()['success'] is False

    # 3. Login with email
    login_res = client.post('/api/v1/auth/login', json={
        "email_or_phone": "marcus@rome.org",
        "password": "Meditations2026!"
    })
    assert login_res.status_code == 200
    assert "access_token" in login_res.get_json()['data']['tokens']

    # 4. Login with phone
    login_phone = client.post('/api/v1/auth/login', json={
        "email_or_phone": "+14155550100",
        "password": "Meditations2026!"
    })
    assert login_phone.status_code == 200

    # 5. Login with invalid password
    bad_login = client.post('/api/v1/auth/login', json={
        "email_or_phone": "marcus@rome.org",
        "password": "WrongPassword!"
    })
    assert bad_login.status_code == 401


def test_profile_authorization_and_update(client, authenticated_user):
    headers = authenticated_user['headers']
    
    # 1. Access without token should be 401 Unauthorized
    unauth = client.get('/api/v1/auth/profile')
    assert unauth.status_code == 401

    # 2. Access with valid token
    auth_res = client.get('/api/v1/auth/profile', headers=headers)
    assert auth_res.status_code == 200
    assert auth_res.get_json()['data']['user']['email'] == authenticated_user['user']['email']

    # 3. Update profile with separated grace period configurations
    update_res = client.put('/api/v1/auth/profile', headers=headers, json={
        "medical_notes": "Asthma - carries rescue inhaler",
        "checkin_grace_period_minutes": 15,
        "pre_alert_countdown_seconds": 30,
        "default_emergency_number": "999"
    })
    assert update_res.status_code == 200
    user_updated = update_res.get_json()['data']['user']
    assert user_updated['medical_notes'] == "Asthma - carries rescue inhaler"
    assert user_updated['checkin_grace_period_minutes'] == 15
    assert user_updated['pre_alert_countdown_seconds'] == 30
    assert user_updated['default_emergency_number'] == "999"
