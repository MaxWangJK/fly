import pytest
import json
from app.merge_policy import merge_fields, disambiguate_unique_fields


def test_different_review_questions_merge_and_clear_does_not_remove_other_answers():
    clocks = {'answers_json': [5000, 'home'], 'answers_json/work': [1000, 'base'],
              'answers_json/home': [5000, 'home']}
    data = merge_fields({'answers_json': '{"work":"base","home":"Home answer"}'},
        {'answers_json': '{"work":"Work answer","home":""}'}, ['answers_json'], {'answers_json'}, clocks,
        {'answers_json': [4000, 'work'], 'answers_json/work': [4000, 'work'],
         'answers_json/home': [1000, 'base']}, 'work', 10000)
    assert json.loads(data['answers_json']) == {'work': 'Work answer', 'home': 'Home answer'}
    cleared = merge_fields(data, {'answers_json': '{"home":"Home answer"}'}, ['answers_json'], {'answers_json'}, clocks,
        {'answers_json/work': [6000, 'clear'], 'answers_json/home': [5000, 'home']}, 'clear', 10000)
    assert json.loads(cleared['answers_json']) == {'home': 'Home answer'}


@pytest.mark.parametrize('edits', [
    [(3000, 'a', 'old'), (5000, 'b', 'new')],
    [(5000, 'b', 'new'), (3000, 'a', 'old')],
    [(5000, 'a', 'old'), (5000, 'b', 'new')],
    [(5000, 'b', 'new'), (5000, 'a', 'old')],
])
def test_offline_edit_order_and_equal_timestamp_ties(edits):
    data, clocks = {'phone': 'base', 'address': 'unchanged'}, {'phone': [1000, 'base']}
    for at, mid, value in edits:
        data = merge_fields(data, {'phone': value}, ['phone'], {'phone'}, clocks,
                            {'phone': [at, mid]}, mid, 10000)
    assert data == {'phone': 'new', 'address': 'unchanged'}


def test_causal_clear_and_bounded_future_clock():
    clocks = {'phone': [5000, 'old']}
    data = merge_fields({'phone': 'value'}, {'phone': ''}, ['phone'], set(), clocks,
                        {'phone': [1000, 'new']}, 'new', 10000)
    assert data['phone'] == '' and clocks['phone'][0] == 5001
    merge_fields(data, {'phone': 'future'}, ['phone'], {'phone'}, clocks,
                 {'phone': [99999999999999, 'future']}, 'future', 10000)
    assert clocks['phone'][0] == 10000


def test_unique_order_labels_and_independent_same_name_customers():
    order = {'id': 'home', 'order_number': 'ORD001', 'customer_id': 'home-customer'}
    disambiguate_unique_fields('orders', '12345678-1234-1234-1234-123456789012', order,
                               [{'id': 'work', 'order_number': 'ORD001'}])
    assert order == {'id': 'home', 'order_number': 'ORD001 (123456781234)', 'customer_id': 'home-customer'}
    name = 'x' * 80
    label = {'id': 'home', 'scope': 'customer', 'name': name}
    disambiguate_unique_fields('tags', '12345678-1234-1234-1234-123456789012', label,
                              [{'id': 'work', 'scope': 'customer', 'name': name}])
    assert len(label['name']) == 80
    emoji = '🙂' * 40
    label = {'id': 'home', 'scope': 'customer', 'name': emoji}
    disambiguate_unique_fields('tags', '12345678-1234-1234-1234-123456789012', label,
                              [{'id': 'work', 'scope': 'customer', 'name': emoji}])
    assert len(label['name'].encode('utf-16-le')) // 2 <= 80
    assert label['name'].encode('utf-8')
