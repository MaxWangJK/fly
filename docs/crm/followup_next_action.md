# Follow-up Next Action

The follow-up extension keeps the main communication field and adds one optional lightweight “下一步” field.

- Enter in the main field saves; Shift+Enter inserts a newline.
- Saving clears both fields and returns focus to the main field.
- The detail header reads the newest non-empty `CustomerFollowUp.nextAction`, ordered by `followedUpAt DESC`.
- A newer follow-up with an empty next action does not erase the latest useful action.
- `Customer.nextAction` is retained only for database compatibility and is not the detail header's source of truth.
