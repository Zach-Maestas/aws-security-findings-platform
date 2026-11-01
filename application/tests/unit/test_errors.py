def test_unknown_route_returns_404_in_error_shape(client):
    response = client.get("/does-not-exist")

    assert response.status_code == 404
    assert response.json() == {
        "error": {"code": "not_found", "message": "Not Found", "details": None}
    }


def test_wrong_method_returns_405(client):
    response = client.delete("/health")

    assert response.status_code == 405
    assert response.json()["error"]["code"] == "method_not_allowed"
